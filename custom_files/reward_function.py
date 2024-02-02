import math
import sys
import time

import numpy
import rospy


MAX_SPEED = 4.0
ABS_MAX_STEERING_ANGLE = 30
MIN_SPEED = 1.5
FPS = 15
MAX_SPEED_DIFF = MAX_SPEED - 0
segment_angle_threshold = 5
curve_angle_threshold = 70
curve_distance_ratio_threshold = 1
max_heading_error = 90
waypoint_lookahead_distance = 3
lookahead_track_width_factor = 1

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
        perp_intercept = y1 - perp_slope * x1
        return cls(perp_slope, perp_intercept, Point(x1, y1))


class RunState:

    def __init__(self, params, prev_run_state, fps):
        self._set_raw_inputs(params)
        self._set_derived_inputs(fps)
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

    def _set_derived_inputs(self, fps):
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
        self.max_distance_traveled = self.steps * MAX_SPEED / FPS
        self.max_progress_percentage = self.max_distance_traveled / self.track_length
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
            'curve_factor': self.curve_factor,
            'waypoint_heading_reward': self.waypoint_heading_reward,
            'steering_reward': self.steering_reward,
            'abs_steering_reward': self.abs_steering_reward,
            'target_steering_reward': self.target_steering_reward,
            'center_line_reward': self.center_line_reward,
            'reward': self.reward
        }
        messages = [self.validate_field(k, v) for k, v in validation_dict.items()]
        exc_messages = [m for m in messages if m]
        if exc_messages:
            raise Exception('\n'.join(exc_messages))

    @property
    def reward(self):
        reward = self.speed_ratio * self.progress_reward * (self.center_line_reward + self.waypoint_heading_reward + self.steering_reward) / 3
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
            'curve_factor': self.curve_factor,
            'waypoint_heading_reward': self.waypoint_heading_reward,
            'steering_reward': self.steering_reward,
            'speed_reward': self.speed_reward,
            'progress_reward': self.progress_reward,
            'center_line_reward': self.center_line_reward,
        }

    @property
    def progress_reward(self):
        return self.progress_percentage

    @property
    def steering_reward(self):
        # We want to reward for both being on target and for requiring a small steering angle
        steering_reward = self.abs_steering_reward * self.target_steering_reward
        return steering_reward

    @property
    def abs_steering_reward(self):
        return math.cos(math.radians(self.steering_angle) * self.curve_factor)

    @property
    def target_steering_reward(self):
        abs_steering_diff = min(abs(self.target_steering_angle - self.steering_angle), ABS_MAX_STEERING_ANGLE)
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
        sqrt_factor = min_distance_factor - mod_distance_factor
        return math.sqrt(1 - (sqrt_factor - .5) ** 2)

    @property
    def waypoint_heading_reward(self):
        '''
        Reward for heading towards the next waypoint
        Reward is based on the heading error between the car and the current waypoint segment
        '''
        next_wp = track_waypoints.waypoints_map[self.closest_ahead_waypoint_index]
        start_x, start_y = self.x, self.y
        end_x, end_y = next_wp.x, next_wp.y
        for i in range(waypoint_lookahead_distance):
            start_x, start_y = end_x, end_y
            next_wp = next_wp.next_waypoint
            end_x, end_y = next_wp.x, next_wp.y

        segment = LinearFunction.from_points(start_x, start_y, end_x, end_y)
        perp_waypoint_func = LinearFunction.get_perp_func(end_x, end_y, segment.slope)
        target_point = perp_waypoint_func.get_closest_point_on_line(self.x, self.y)
        start_point = Point(self.x, self.y)
        end_point = Point(target_point.x, target_point.y)
        target_line = LineSegment(start_point, end_point)

        heading_error = min(abs(target_line.angle - self.heading360), max_heading_error)
        heading_factor = math.cos(math.radians(heading_error))
        return heading_factor

    @property
    def speed_reward(self):
        # noinspection PyAttributeOutsideInit
        speed_diff_factor = abs(self.speed - self.target_speed) / MAX_SPEED_DIFF
        reward = math.exp(-speed_diff_factor)
        # noinspection PyChainedComparisons
        if self.speed == self.target_speed:
            return reward
        elif self.prev_speed:
            if self.target_speed > self.speed:
                if self.prev_speed < self.speed:
                    speed_factor = 1 + speed_diff_factor
                else:
                    speed_factor = 1 - speed_diff_factor
                return reward * speed_factor / 2
            elif self.target_speed < self.speed:
                if self.prev_speed > self.speed:
                    speed_factor = 1 + speed_diff_factor
                else:
                    speed_factor = 1 - speed_diff_factor
                return reward * speed_factor / 2
        else:
            return reward / 2

    @property
    def next_speed_reward(self):
        speed_diff_factor = abs(self.speed - self.target_speed) / MAX_SPEED_DIFF
        reward = math.exp(-speed_diff_factor)
        # noinspection PyChainedComparisons
        if self.speed == self.target_speed:
            return reward
        elif self.prev_run_state:
            prev_desired_target_diff = self.prev_run_state.target_speed - self.prev_run_state.speed
            observed_speed_change = self.speed - self.prev_run_state.speed
            observed_speed_prev_target_diff = self.speed - self.prev_run_state.target_speed
            observed_speed_prev_target_ratio = observed_speed_prev_target_diff / MAX_SPEED_DIFF
            if prev_desired_target_diff != 0:
                observed_change_needed_change_ratio = observed_speed_change / prev_desired_target_diff
                # symmetrical function with max 1 at 1
                prev_change_reward = math.exp(-((observed_change_needed_change_ratio - 1) ** 2))
                # symmetrical function with max 1 at 0 TODO y=sqrt(1-(x-1)^2)
                prev_desired_reward = math.exp(-(observed_speed_prev_target_ratio ** 2))
            else:
                prev_desired_reward = 1
                prev_change_reward = 1
            return reward * prev_desired_reward * prev_change_reward
        else:
            return reward

    @property
    def target_speed(self):
        curve_param = self.curve_factor * self.steering_reward
        return MIN_SPEED + (MAX_SPEED - MIN_SPEED) * curve_param

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
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        next_segment = segment.next_segment

        lookahead_segment = next_segment
        lookahead_length = next_segment.length
        while lookahead_length < self.track_width * lookahead_track_width_factor:
            lookahead_segment = lookahead_segment.next_segment
            lookahead_length += lookahead_segment.length
        lookahead_start = lookahead_segment.start
        lookahead_distance = math.sqrt((lookahead_start.x - self.x) ** 2 + (lookahead_start.y - self.y) ** 2)
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
    def curve_lookahead_segment(self):
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        next_segment = segment.next_segment
        dist_to_next_segment = math.sqrt((next_segment.start.x - self.x) ** 2 + (next_segment.start.y - self.y) ** 2)
        lookahead_segment = next_segment
        lookahead_length = next_segment.length + dist_to_next_segment
        while lookahead_length < self.track_width * lookahead_track_width_factor * 2:
            lookahead_segment = lookahead_segment.next_segment
            lookahead_length += lookahead_segment.length
        return lookahead_segment

    @property
    def next_segment_start_distance_ratio(self):
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        next_segment = segment.next_segment
        next_segment_start = next_segment.start
        next_segment_distance = math.sqrt((next_segment_start.x - self.x) ** 2 + (next_segment_start.y - self.y) ** 2)
        return next_segment_distance / self.track_width

        max_angle_diff = 90
        angle_diff = min(abs(lookahead_segment.angle - self.heading360), max_angle_diff)
        angle_diff_radians = math.radians(angle_diff)
        curve_factor = math.cos(angle_diff_radians)
        if curve_distance_ratio < curve_distance_ratio_threshold and angle_diff > curve_angle_threshold:
            return curve_factor
        else:
            return 1


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
        self.total_frames += frames
        print("TIME: s: {}, rtf: {}, fps:{}, frames: {}".format(int(steps), round(self.rtf, 2), round(self.fps, 2), frames))


class Simulation:
    __slots__ = 'sim_state_initialized', 'run_state', 'timer'

    def __init__(self):
        self.sim_state_initialized = False
        self.run_state = None
        self.timer = Timer()

    def add_run_state(self, params):
        if not self.sim_state_initialized:
            track_waypoints.create_waypoints(params['waypoints'])
            track_segments.create_segments(track_waypoints.waypoints)
            self.sim_state_initialized = True

        steps = params['steps']
        self.timer.record_time(steps)
        run_state = RunState(params, self.run_state, 15)
        run_state.validate()
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
    return sim.run_state.reward
