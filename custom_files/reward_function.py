# TODO SIMPLE CHECKS TO RETURN MIN_REWARD. CAN ALSO DO PREV CHECKS TO RETURN MIN_REWARD

import math
import sys
import time

import numpy
import rospy
from shapely import LinearRing, LineString, Point


LineString()
LinearRing()
MIN_REWARD = 1e-5
MAX_SPEED = 5.0
ABS_MAX_STEERING_ANGLE = 30
MIN_SPEED = 1.9
FPS = 15
PREV_DISCOUNT_FACTOR = 0.1
PREV_DISCOUNT_DIVISOR = 1 + PREV_DISCOUNT_FACTOR
REWARD_BONUS = 1.1
MAX_SPEED_DIFF = MAX_SPEED - 0
MAX_COLLINEAR_SEGMENT_ANGLE_THRESHOLD = 5
CURVE_ANGLE_THRESHOLD = 70
NEXT_SEGMENT_CLOSE_RATIO_THRESHOLD = 1
CURVE_DISTANCE_MAX_LOOKAHEAD_RATIO = 2
MAX_HEADING_ERROR = 90
WAYPOINT_LOOKAHEAD_DISTANCE = 3
LOOKAHEAD_TRACK_WIDTH_RATIO = 1


INF = float('inf')
NINF = -INF


def get_nan(numerator):
    return INF if numerator >= 0 else NINF


class TrackPoint(Point):
    __slots__ = 'x', 'y'

    def __init__(self, x, y):
        super().__init__([x, y])
        self.x = x
        self.y = y


class Waypoint(TrackPoint):
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


class LineSegment(LineString):
    __slots__ = 'start', 'end', 'slope', 'angle', 'length'

    def __init__(self, start, end):
        super().__init__([start, end])
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

class TrackLinearRing(LinearRing):
    def __init__(self, points):
        super().__init__(points)

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

        if prev_segment and abs(prev_segment.angle - angle) < MAX_COLLINEAR_SEGMENT_ANGLE_THRESHOLD:
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


track_segments = None
track_waypoints = None



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
            return TrackPoint(self.ref_point.x, y)
        else:
            x = (self.B * (self.B * x - self.A * y) - self.A * self.C) / (self.A ** 2 + self.B ** 2)
            y = (self.A * (-self.B * x + self.A * y) - self.B * self.C) / (self.A ** 2 + self.B ** 2)
            return TrackPoint(x, y)

    @classmethod
    def from_points(cls, x1, y1, x2, y2):
        slope = (y2 - y1) / (x2 - x1) if x2 != x1 else get_nan(y2 - y1)
        intercept = y1 - slope * x1
        return cls(slope, intercept, TrackPoint(x1, y1))

    @classmethod
    def get_perp_func(cls, x1, y1, slope):
        perp_slope = -1 / slope if slope != 0 else -slope
        perp_intercept = y1 - perp_slope * x1
        return cls(perp_slope, perp_intercept, TrackPoint(x1, y1))


class LookaheadData:
    __slots__ = 'segments', 'init_segment', 'total_distance', 'abs_total_angle_changes', 'total_angle_changes'

    def __init__(self, init_segment: LineSegment, init_angle_diff):
        self.segments = []
        self.init_segment = init_segment
        self.total_distance = init_segment.length
        self.total_angle_changes = init_angle_diff
        self.abs_total_angle_changes = abs(init_angle_diff)


    def add_segment(self, segment):
        self.segments.append(segment)
        self.total_distance += segment.length
        angle_diff = segment.angle - segment.prev_segment.angle
        self.total_angle_changes += angle_diff
        self.abs_total_angle_changes += abs(segment.angle - segment.prev_segment.angle)


class RunState:

    def __init__(self, params, prev_run_state, max_progress_advancement):
        self._set_raw_inputs(params)
        self._set_derived_inputs(max_progress_advancement)
        self._set_future_inputs()
        self.prev_run_state = prev_run_state
        self._set_prev_inputs()

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
        messages = [self.validate_field(k, v) for k, v in self.reward_data.items() if 'data' not in k]
        exc_messages = [m for m in messages if m]
        if exc_messages:
            raise Exception('\n'.join(exc_messages))

    @property
    def additive_factors(self):
        return self.center_line_reward, self.waypoint_heading_reward, self.steering_reward

    @property
    def multiplicative_factors(self):
        return self.next_speed_reward, self.progress_reward

    @property
    def additive_reward(self):
        return math.fsum(self.additive_factors) / len(self.additive_factors)

    @property
    def multiplicative_reward(self):
        return math.prod(self.multiplicative_factors)

    @property
    def reward(self):
        reward = self.additive_reward * self.multiplicative_reward
        if self.all_wheels_on_track and not self.is_crashed and not self.is_offtrack and not self.is_reversed:
            return max(reward, MIN_REWARD)
        else:
            return MIN_REWARD

    @property
    def reward_data(self):
        return {
            'reward': self.reward,
            'progress': self.progress_percentage,
            'next_curve_factor': self.next_segment_curve_factor,
            'target_speed_data': self.target_speed,
            'curve_factor': self.curve_factor,
            'waypoint_heading_reward': self.waypoint_heading_reward,
            'steering_reward': self.steering_reward,
            'next_speed_reward': self.next_speed_reward,
            'progress_reward': self.progress_reward,
            'center_line_reward': self.center_line_reward,
        }

    @property
    def progress_reward(self):
        return self.progress_percentage

    @property
    def progress_advancement(self):
        if self.prev_run_state:
            return self.progress_percentage - self.prev_run_state.progress_percentage
        else:
            return self.progress_percentage

    @property
    def progress_advancement_reward(self):
        return self.progress_advancement


    @property
    def steering_reward(self):
        # We want to reward for both being on target and for requiring a small steering angle
        steering_reward = self.target_steering_reward
        return steering_reward

    # noinspection PyUnusedFunction
    @property
    def abs_steering_reward(self):
        return math.cos(math.radians(self.steering_angle) * self.curve_factor)

    @property
    def target_steering_reward(self):
        abs_steering_diff = min(abs(self.target_steering_angle - self.steering_angle), ABS_MAX_STEERING_ANGLE)
        return math.cos(math.radians(abs_steering_diff))

    @property
    def target_steering_angle(self):
        return min(ABS_MAX_STEERING_ANGLE, self.heading_error) if self.heading_error > 0 else max(-ABS_MAX_STEERING_ANGLE, self.heading_error)

    @property
    def center_line_reward(self):
        '''
        Reward for being close to the center line
        Reward is exponentially based on distance from center line with max reward at quarter track width
        and minimum reward at half track width
        '''

        if self.next_segment_semidistant and self.large_curve_ahead:
            if self.curve_lookahead_data.total_angle_changes < 0:
                if self.is_left_of_center:
                    turn_side_bonus = 0.9
                else:
                    turn_side_bonus = 1.1
            else:
                if self.is_left_of_center:
                    turn_side_bonus = 1.1
                else:
                    turn_side_bonus = 0.9
        else:
            turn_side_bonus = 1

        min_distance_factor = self.quarter_track_width / self.half_track_width
        max_distance_factor = self.half_track_width / self.half_track_width
        distance_factor = self.distance_from_center / self.half_track_width
        mod_distance_factor = max(min(max_distance_factor, distance_factor), min_distance_factor) * self.curve_factor
        sqrt_factor = min_distance_factor - mod_distance_factor
        return math.sqrt(1 - (sqrt_factor - .5) ** 2) * turn_side_bonus / 1.1

    @property
    def target_point(self):
        next_wp = track_waypoints.waypoints_map[self.closest_ahead_waypoint_index]
        start_x, start_y = self.x, self.y
        end_x, end_y = next_wp.x, next_wp.y
        for i in range(WAYPOINT_LOOKAHEAD_DISTANCE):
            start_x, start_y = end_x, end_y
            next_wp = next_wp.next_waypoint
            end_x, end_y = next_wp.x, next_wp.y

        segment = LinearFunction.from_points(start_x, start_y, end_x, end_y)
        perp_waypoint_func = LinearFunction.get_perp_func(end_x, end_y, segment.slope)
        return perp_waypoint_func.get_closest_point_on_line(self.x, self.y)

    @property
    def target_line(self):
        start_point = TrackPoint(self.x, self.y)
        end_point = TrackPoint(self.target_point.x, self.target_point.y)
        return LineSegment(start_point, end_point)

    @property
    def heading_error(self):
        return self.target_line.angle - self.heading360

    @property
    def waypoint_heading_reward(self):
        '''
        Reward for heading towards the next waypoint
        Reward is based on the heading error between the car and the current waypoint segment
        '''

        heading_factor = min(abs(self.heading_error), MAX_HEADING_ERROR)
        return math.cos(math.radians(heading_factor))


    @property
    def next_speed_reward(self):
        speed_diff_factor = abs(self.speed - self.target_speed) / MAX_SPEED_DIFF
        reward = math.sqrt(1 - speed_diff_factor ** 2)
        # noinspection PyChainedComparisons
        if self.speed == self.target_speed:
            return reward
        elif self.prev_run_state:
            prev_desired_target_diff = self.prev_run_state.target_speed - self.prev_run_state.speed
            observed_speed_change = self.speed - self.prev_run_state.speed
            if prev_desired_target_diff != 0:
                observed_change_needed_change_ratio = observed_speed_change / prev_desired_target_diff
                prev_change_reward = math.exp(-((observed_change_needed_change_ratio - 1) ** 2))
            else:
                prev_change_reward = 1
            return (reward + PREV_DISCOUNT_FACTOR * prev_change_reward) / PREV_DISCOUNT_DIVISOR
        else:
            return reward

    @property
    def target_speed(self):
        curve_param = self.curve_factor
        return MIN_SPEED + (MAX_SPEED - MIN_SPEED) * curve_param


    @property
    def curve_factor(self):
        return self.next_segment_curve_factor
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        next_segment = segment.next_segment

        lookahead_segment = next_segment
        lookahead_length = next_segment.length
        while lookahead_length < self.track_width * LOOKAHEAD_TRACK_WIDTH_RATIO:
            lookahead_segment = lookahead_segment.next_segment
            lookahead_length += lookahead_segment.length
        lookahead_start = lookahead_segment.start
        lookahead_distance = math.sqrt((lookahead_start.x - self.x) ** 2 + (lookahead_start.y - self.y) ** 2)
        curve_distance_ratio = lookahead_distance / self.track_width

        max_angle_diff = 90
        angle_diff = min(abs(lookahead_segment.angle - self.heading360), max_angle_diff)
        angle_diff_radians = math.radians(angle_diff)
        curve_factor = math.cos(angle_diff_radians)
        if curve_distance_ratio < NEXT_SEGMENT_CLOSE_RATIO_THRESHOLD and angle_diff > CURVE_ANGLE_THRESHOLD:
            return curve_factor
        else:
            return 1

    @property
    def curve_lookahead_data(self):
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        next_segment = segment.next_segment
        init_segment = LineSegment(self.location, next_segment.start)
        lookahead_data = LookaheadData(init_segment, init_segment.angle - self.heading360)
        lookahead_segment = next_segment
        lookahead_data.add_segment(lookahead_segment)
        while lookahead_data.total_distance < self.track_width * LOOKAHEAD_TRACK_WIDTH_RATIO:
            lookahead_segment = lookahead_segment.next_segment
            lookahead_data.add_segment(lookahead_segment)

        return lookahead_data


    @property
    def next_segment_start_distance_ratio(self):
        segment = track_segments.get_closest_segment(self.closest_ahead_waypoint_index)
        next_segment = segment.next_segment
        next_segment_start = next_segment.start
        next_segment_distance = math.sqrt((next_segment_start.x - self.x) ** 2 + (next_segment_start.y - self.y) ** 2)
        return next_segment_distance / self.track_width

    @property
    def next_segment_close(self):
        return self.next_segment_start_distance_ratio < NEXT_SEGMENT_CLOSE_RATIO_THRESHOLD

    @property
    def next_segment_semidistant(self):
        return CURVE_DISTANCE_MAX_LOOKAHEAD_RATIO > self.next_segment_start_distance_ratio > NEXT_SEGMENT_CLOSE_RATIO_THRESHOLD

    @property
    def large_curve_ahead(self):
        return self.curve_lookahead_data.abs_total_angle_changes > CURVE_ANGLE_THRESHOLD

    @property
    def next_segment_curve_factor(self):
        if self.next_segment_start_distance_ratio > CURVE_DISTANCE_MAX_LOOKAHEAD_RATIO:
            return 1
        elif self.next_segment_close and self.large_curve_ahead:
            return 0
        elif self.next_segment_semidistant and self.large_curve_ahead:
            return self.next_segment_start_distance_ratio - 1
        else:
            return 1

    # noinspection PyUnusedFunction
    def set_next_state(self, next_state):
        self.next_state = next_state

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

    def _set_prev_inputs(self):
        if self.prev_run_state:
            self.acceleration = self.speed - self.prev_run_state.speed
        else:
            self.acceleration = self.speed

    def _set_derived_inputs(self, max_progress_advancement):
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
        self.location = TrackPoint(self.x, self.y)

    def _set_future_inputs(self):
        self.next_x = self.x + self.x_velocity / FPS
        self.next_y = self.y + self.y_velocity / FPS


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
    __slots__ = 'sim_state_initialized', 'run_state', 'timer', 'progress_advancements'

    def __init__(self):
        self.sim_state_initialized = False
        self.run_state = None
        self.timer = Timer()
        self.progress_advancements = []

    def add_run_state(self, params):
        if not self.sim_state_initialized:
            track_waypoints = TrackWaypoints()
            track_segments = TrackSegments()
            track_waypoints.create_waypoints(params['waypoints'])
            track_segments.create_segments(track_waypoints.waypoints)
            self.sim_state_initialized = True

        steps = params['steps']
        self.timer.record_time(steps)
        max_progress_advancement = max(self.progress_advancements) if self.progress_advancements else None
        run_state = RunState(params, self.run_state, max_progress_advancement)
        print(run_state.reward_data)

        run_state.validate()
        self.progress_advancements.append(run_state.progress_advancement)
        self.run_state = run_state
        size_data = {
            'sim': sys.getsizeof(self),
            'run_state': sys.getsizeof(run_state),
            'params': sys.getsizeof(params),
            'track_waypoints': sys.getsizeof(track_waypoints),
            'track_segments': sys.getsizeof(track_segments),
            'timer': sys.getsizeof(self.timer),
        }
        '''
        {'sim': 72, 'run_state': 56, 'params': 1184, 'track_waypoints': 56, 'track_segments': 48, 'timer': 80}

        '''



sim = Simulation()


# noinspection PyUnusedFunction
def reward_function(params):
    '''
    Example of penalize steering, which helps mitigate zig-zag behaviors
    '''
    sim.add_run_state(params)
    return sim.run_state.reward
