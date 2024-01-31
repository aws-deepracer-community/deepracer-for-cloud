import math
import sys
import time

import numpy
import rospy


MAX_SPEED = 4.0
ABS_MAX_STEERING_ANGLE = 20
MIN_SPEED = 1.75
MAX_SPEED_DIFF = MAX_SPEED - 0
segment_angle_threshold = 5
curve_angle_threshold = 75
curve_distance_ratio_threshold = 1
max_heading_error = 90
waypoint_lookahead_distance = 1
lookahead_track_width_factor = 1
FPS = 15
INF = float('inf')
NINF = -INF


def get_nan(numerator):
    return INF if numerator >= 0 else NINF


class Point:
    __slots__ = 'x', 'y'

    def __init__(self, x, y):
        self.x = x
        self.y = y


class Waypoint(Point):
    __slots__ = 'x', 'y', 'index', 'next_waypoint', 'prev_waypoint'

    def __init__(self, x, y, index, prev_waypoint):
        super().__init__(x, y)
        self.index = index
        self.next_waypoint = None
        self.prev_waypoint = prev_waypoint

    def set_prev_waypoint(self, waypoint):
        self.prev_waypoint = waypoint

    def set_next_waypoint(self, waypoint):
        self.next_waypoint = waypoint


class LineSegment:
    __slots__ = 'start', 'end', 'slope', 'angle', 'length'

    def __init__(self, start, end):
        self.start = start
        self.end = end
        numerator = (self.end.y - self.start.y)
        self.slope = numerator / (self.end.x - self.start.x) if self.end.x != self.start.x else get_nan(numerator)
        radians = math.atan2(self.end.y - self.start.y, self.end.x - self.start.x)
        self.angle = math.degrees(radians)
        self.length = math.sqrt((self.end.x - self.start.x) ** 2 + (self.end.y - self.start.y) ** 2)


class LinearWaypointSegment(LineSegment):
    __slots__ = 'start', 'end', 'waypoints', 'waypoint_indices', 'prev_segment', 'next_segment'

    def __init__(self, start, end, prev_segment):
        super().__init__(start, end)
        self.waypoint_indices = {start.index, end.index}
        self.prev_segment = prev_segment
        self.next_segment = None

    def add_waypoint(self, waypoint):
        self.end = waypoint
        self.waypoint_indices.add(waypoint.index)

    def set_next_segment(self, segment):
        self.next_segment = segment

    def set_prev_segment(self, segment):
        self.prev_segment = segment


class TrackWaypoints:
    __slots__ = 'waypoints', 'waypoints_map'

    def __init__(self):
        self.waypoints = []
        self.waypoints_map = {}

    def create_waypoints(self, waypoints):
        for i, wp in enumerate(waypoints):
            prev_waypoint = self.waypoints[-1] if self.waypoints else None
            waypoint = Waypoint(wp[0], wp[1], i, prev_waypoint)

            if prev_waypoint:
                prev_waypoint.set_next_waypoint(waypoint)

            self.waypoints.append(waypoint)
            self.waypoints_map[i] = waypoint
        first_waypoint = self.waypoints[0]
        last_waypoint = self.waypoints[-1]
        last_waypoint.set_next_waypoint(first_waypoint)
        first_waypoint.set_prev_waypoint(last_waypoint)


# noinspection DuplicatedCode
class TrackSegments:
    __slots__ = 'segments'

    def __init__(self):
        self.segments = []

    def add_waypoint_segment(self, start, end):
        radians = math.atan2(end.y - start.y, end.x - start.x)
        angle = math.degrees(radians)
        prev_segment = self.segments[-1] if self.segments else None

        if prev_segment and abs(prev_segment.angle - angle) < segment_angle_threshold:
            prev_segment.add_waypoint(end)
        else:
            segment = LinearWaypointSegment(start, end, prev_segment)
            if self.segments:
                prev_segment.set_next_segment(segment)
            self.segments.append(segment)

    def create_segments(self, waypoints):
        for i in range(len(waypoints) - 1):
            start = waypoints[i]
            end = waypoints[i + 1]
            self.add_waypoint_segment(start, end)
        self.add_waypoint_segment(waypoints[-1], waypoints[0])
        first_segment = self.segments[0]
        last_segment = self.segments[-1]
        last_segment.set_next_segment(first_segment)
        first_segment.set_prev_segment(last_segment)


    def get_closest_segment(self, closest_ahead_waypoint_index):
        for segment in self.segments:
            if closest_ahead_waypoint_index in segment.waypoint_indices:
                return segment
        raise Exception('No segment found for closest waypoint index: {}'.format(closest_ahead_waypoint_index))


track_segments = TrackSegments()
track_waypoints = TrackWaypoints()


def get_slope_intercept(x1, y1, m):
    return y1 - m * x1


class LinearFunction:
    __slots__ = 'slope', 'intercept', 'A', 'B', 'C', 'ref_point'

    # noinspection PyUnusedFunction
    def __init__(self, slope, intercept, ref_point=None):
        self.slope = slope
        self.intercept = intercept
        self.B = 1
        self.A = -self.slope
        self.C = -self.intercept
        self.ref_point = ref_point

    def get_closest_point_on_line(self, x, y):
        if not math.isfinite(self.slope) or not math.isfinite(self.A) or not math.isfinite(self.C) or not math.isfinite(self.intercept):
            return Point(self.ref_point.x, y)
        else:
            x = (self.B * (self.B * x - self.A * y) - self.A * self.C) / (self.A ** 2 + self.B ** 2)
            y = (self.A * (-self.B * x + self.A * y) - self.B * self.C) / (self.A ** 2 + self.B ** 2)
            return Point(x, y)

    @classmethod
    def from_points(cls, x1, y1, x2, y2):
        slope = (y2 - y1) / (x2 - x1) if x2 != x1 else get_nan(y2 - y1)
        intercept = y1 - slope * x1
        return cls(slope, intercept, Point(x1, y1))

    @classmethod
    def get_perp_func(cls, x1, y1, slope):
        perp_slope = -1 / slope if slope != 0 else -slope
        perp_intercept = get_slope_intercept(x1, y1, perp_slope)
        return cls(perp_slope, perp_intercept, Point(x1, y1))


def get_point_distance(x1, y1, x2, y2):
    return math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)


class RunState:

    def __init__(self, params, prev_run_state, max_progress_advancement):
        self._set_raw_inputs(params)
        self._set_derived_inputs(max_progress_advancement)
        self._set_future_inputs()
        self.prev_run_state = prev_run_state
        self._set_prev_inputs()

    def set_next_state(self, next_state):
        self.next_state = next_state

    def _set_prev_inputs(self):
        if self.prev_run_state:
            self.prev_speed = self.prev_run_state.speed
            self.prev_steering_angle = self.prev_run_state.steering_angle
            self.prev_heading360 = self.prev_run_state.heading360
        else:
            self.prev_speed = None

    def _set_derived_inputs(self, max_progress_advancement):
        self.max_progress_advancement = max_progress_advancement
        self.progress_val = (self.progress / 100)
        self.speed_ratio = self.speed / MAX_SPEED
        self.heading360 = self.heading if self.heading >= 0 else 360 + self.heading
        self.abs_steering_angle = abs(self.steering_angle)
        self.x_velocity = self.speed * math.cos(math.radians(self.heading360))
        self.y_velocity = self.speed * math.sin(math.radians(self.heading360))
        self.next_x = self.x + self.x_velocity / FPS
        self.next_y = self.y + self.y_velocity / FPS
        self.closest_behind_waypoint_index = self.closest_waypoints[0]
        self.closest_ahead_waypoint_index = self.closest_waypoints[1]
        self.half_track_width = self.track_width / 2
        self.quarter_track_width = self.half_track_width / 2
        self.progress_percentage = self.progress / 100

    def _set_future_inputs(self):
        self.x_velocity = self.speed * math.cos(math.radians(self.heading360))
        self.y_velocity = self.speed * math.sin(math.radians(self.heading360))
        self.next_x = self.x + self.x_velocity / FPS
        self.next_y = self.y + self.y_velocity / FPS

    def validate_field(self, field, value):
        if value is None:
            return f'{field}: {value} is None'
        elif value > 1:
            return f'{field}: {value} is greater than 1'
        elif value < 0:
            return f'{field}: {value} is less than 0. Found '
        elif not math.isfinite(value):
            return f'{field}: {value} is not finite'
        else:
            return None
    def validate(self):
        validation_dict = {
            'speed_ratio': self.speed_ratio,
            'progress_reward': self.progress_reward,
            'progress_advancement_reward': self.progress_advancement_reward,
            'curve_factor': self.curve_factor,
            'waypoint_heading_reward': self.waypoint_heading_reward,
            'steering_reward': self.steering_reward,
            'center_line_reward': self.center_line_reward,
            'reward': self.reward
        }
        messages = [self.validate_field(k, v) for k, v in validation_dict.items()]
        exc_messages = [m for m in messages if m]
        if exc_messages:
            raise Exception('\n'.join(exc_messages))

    @property
    def reward(self):
        reward = self.speed_ratio * self.progress_advancement_reward * (self.center_line_reward + self.waypoint_heading_reward + self.steering_reward) / 4
        if self.all_wheels_on_track and not self.is_crashed and not self.is_offtrack and not self.is_reversed:
            return reward
        else:
            return 0.0001

    @property
    def reward_data(self):
        return {
            'reward': self.reward,
            'steps': self.steps,
            'progress': self.progress_percentage,
            'progress_reward': self.progress_reward,
            'progress_advancement_reward': self.progress_advancement_reward,
            'curve_factor': self.curve_factor,
            'waypoint_heading_reward': self.waypoint_heading_reward,
            'steering_reward': self.steering_reward,
            'speed_reward': self.speed_reward,
            'center_line_reward': self.center_line_reward,
        }

    @property
    def progress_reward(self):
        return self.progress_percentage

    @property
    def progress_advancement(self):
        prog_diff = self.progress_percentage
        if self.prev_run_state:
            prog_diff = self.progress_percentage - self.prev_run_state.progress_percentage
        return prog_diff

    @property
    def progress_advancement_reward(self):
        if self.progress_advancement >= self.max_progress_advancement:
            return 1
        elif self.progress_advancement <= 0:
            return 0
        else:
            return self.progress_advancement / self.max_progress_advancement


    @property
    def steering_reward(self):
        return self.target_steering_reward

    @property
    def abs_steering_reward(self):
        abs_steering_factor = math.radians(self.abs_steering_angle) * self.curve_factor
        return math.cos(abs_steering_factor)

    @property
    def target_steering_reward(self):
        abs_steering_diff = min(abs(self.target_steering_angle - self.steering_angle), 90)
        return math.cos(math.radians(abs_steering_diff))

    @property
    def target_steering_angle(self):
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        pre_target_steering = self.heading360 - segment.angle
        return min(ABS_MAX_STEERING_ANGLE, pre_target_steering) if pre_target_steering > 0 else max(-ABS_MAX_STEERING_ANGLE, pre_target_steering)

    @property
    def center_line_reward(self):
        '''
        Reward for being close to the center line
        Reward is exponentially based on distance from center line with max reward at quarter track width
        and minimum reward at half track width
        '''
        min_distance_factor = self.quarter_track_width / self.half_track_width
        max_distance_factor = self.half_track_width / self.half_track_width
        distance_factor = self.distance_from_center / self.half_track_width
        mod_distance_factor = max(min(max_distance_factor, distance_factor), min_distance_factor)
        return math.exp(-mod_distance_factor)

    @property
    def waypoint_heading_reward(self):
        '''
        Reward for heading towards the next waypoint
        Reward is based on the heading error between the car and the current waypoint segment
        '''
        heading_error = min(abs(self.target_line.angle - self.heading360), max_heading_error)
        heading_factor = math.cos(math.radians(heading_error))
        return heading_factor

    @property
    def target_point(self):
        lookahead_start = self.lookahead_segment.start
        lookahead_end = self.lookahead_segment.end

        segment = LinearFunction.from_points(lookahead_start.x, lookahead_start.y, lookahead_end.x, lookahead_end.y)
        perp_waypoint_func = LinearFunction.get_perp_func(lookahead_end.x, lookahead_end.y, segment.slope)
        return perp_waypoint_func.get_closest_point_on_line(self.x, self.y)

    @property
    def target_line(self):
        start_point = Point(self.x, self.y)
        end_point = Point(self.target_point.x, self.target_point.y)
        return LineSegment(start_point, end_point)

    @property
    def speed_reward(self):
        # noinspection PyAttributeOutsideInit
        curve_param = self.curve_factor
        self.target_speed = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * curve_param
        reward = math.exp(-abs(self.speed - self.target_speed) / MAX_SPEED_DIFF)
        # noinspection PyChainedComparisons
        if self.speed == self.target_speed:
            return reward
        elif self.prev_speed:
            speed_diff_factor = abs(self.speed - self.prev_run_state.speed) / MAX_SPEED_DIFF
            if self.prev_run_state.target_speed > self.speed:
                if self.prev_speed < self.speed:
                    speed_factor = 1 + speed_diff_factor
                else:
                    speed_factor = 1 - speed_diff_factor
                return reward * speed_factor / 2
            elif self.prev_run_state.target_speed < self.speed:
                if self.prev_speed > self.speed:
                    speed_factor = 1 + speed_diff_factor
                else:
                    speed_factor = 1 - speed_diff_factor
                return reward * speed_factor / 2
        else:
            return reward / 2
        return reward

    def _set_raw_inputs(self, params):
        self.all_wheels_on_track = params['all_wheels_on_track']
        self.x = params['x']
        self.y = params['y']
        self.closest_objects = params['closest_objects']
        self.closest_waypoints = params['closest_waypoints']
        self.distance_from_center = params['distance_from_center']
        self.is_crashed = params['is_crashed']
        self.is_left_of_center = params['is_left_of_center']
        self.is_offtrack = params['is_offtrack']
        self.is_reversed = params['is_reversed']
        self.heading = params['heading']
        self.objects_distance = params['objects_distance']
        self.objects_heading = params['objects_heading']
        self.objects_left_of_center = params['objects_left_of_center']
        self.objects_location = params['objects_location']
        self.objects_speed = params['objects_speed']
        self.progress = params['progress']
        self.speed = params['speed']
        self.steering_angle = params['steering_angle']
        self.steps = params['steps']
        self.track_length = params['track_length']
        self.track_width = params['track_width']
        self.waypoints = params['waypoints']

    @property
    def curve_factor(self):
        lookahead_segment = self.lookahead_segment
        lookahead_end = lookahead_segment.end
        lookahead_distance = get_point_distance(self.x, self.y, lookahead_end.x, lookahead_end.y)
        curve_distance_ratio = lookahead_distance / self.track_width

        max_angle_diff = 90
        angle_diff = min(abs(lookahead_segment.angle - self.heading360), max_angle_diff)
        angle_diff_radians = math.radians(angle_diff)
        curve_factor = math.cos(angle_diff_radians)
        if curve_distance_ratio < curve_distance_ratio_threshold and angle_diff > curve_angle_threshold:
            return curve_factor
        else:
            return 1

    @property
    def lookahead_segment(self):
        lookahead_segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        lookahead_length = get_point_distance(self.x, self.y, lookahead_segment.end.x, lookahead_segment.end.y)

        while lookahead_length < self.track_width * lookahead_track_width_factor:
            lookahead_segment = lookahead_segment.next_segment
            lookahead_length += lookahead_segment.length
        return lookahead_segment


class Timer:
    __slots__ = 'track_time', 'time', 'total_frames', 'fps', 'rtf'

    def __init__(self):
        self.track_time = True
        TIME_WINDOW = 10
        self.time = numpy.zeros([TIME_WINDOW, 2])
        self.total_frames = 0
        self.fps = 15

    def get_time(self):
        wall_time_incr = numpy.max(self.time[:, 0]) - numpy.min(self.time[:, 0])
        sim_time_incr = numpy.max(self.time[:, 1]) - numpy.min(self.time[:, 1])

        rtf = sim_time_incr / wall_time_incr
        frames = (self.time.shape[0] - 1)
        fps = frames / sim_time_incr

        return rtf, fps, frames

    def record_time(self, steps):
        index = int(steps) % self.time.shape[0]
        self.time[index, 0] = time.time()
        self.time[index, 1] = rospy.get_time()
        self.rtf, self.fps, frames = self.get_time()
        self.total_frames += self.fps
        print("TIME: s: {}, rtf: {}, fps:{}, frames: {}".format(int(steps), round(self.rtf, 2), round(self.fps, 2), frames))


class Simulation:
    __slots__ = 'sim_state_initialized', 'run_state', 'timer', 'progress_advancements'

    def __init__(self):
        self.sim_state_initialized = False
        self.run_state = None
        self.timer = Timer()
        self.progress_advancements = [0]


    def add_run_state(self, params):
        if not self.sim_state_initialized:
            track_waypoints.create_waypoints(params['waypoints'])
            track_segments.create_segments(track_waypoints.waypoints)
            self.sim_state_initialized = True

        steps = params['steps']
        self.timer.record_time(steps)
        run_state = RunState(params, self.run_state, max(self.progress_advancements))
        self.progress_advancements.append(run_state.progress_advancement)
        self.run_state = run_state
        print(self.run_state.reward_data)
        size_data = {
            'sim': sys.getsizeof(self),
            'run_state': sys.getsizeof(run_state),
            'params': sys.getsizeof(params),
            'track_waypoints': sys.getsizeof(track_waypoints),
            'track_segments': sys.getsizeof(track_segments),
            'timer': sys.getsizeof(self.timer),
        }
        print(size_data)


sim = Simulation()


# noinspection PyUnusedFunction
def reward_function(params):
    '''
    Example of penalize steering, which helps mitigate zig-zag behaviors
    '''
    sim.add_run_state(params)
    sim.run_state.validate()
    return sim.run_state.reward
