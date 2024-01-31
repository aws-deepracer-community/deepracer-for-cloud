import time
import math
import numpy

LOCAL_TRAINING = True
if LOCAL_TRAINING:
    import rospy


max_speed = 5
segment_angle_threshold = 5
min_speed = 0.5
curve_angle_threshold = 50
curve_distance_ratio_threshold = 1 / 8
abs_max_steering_angle = 20
INF = float('inf')
NINF = -INF

def get_nan(numerator):
    return INF if numerator >= 0 else NINF

class Point:
    x: float
    y: float

    def __init__(self, x, y):
        self.x = x
        self.y = y


class LineSegment:
    def __init__(self, start, end):
        self.start = start
        self.end = end

    @classmethod
    def from_points(cls, x1, y1, x2, y2):
        start = Point(x1, y1)
        end = Point(x2, y2)
        return cls(start, end)

    @property
    def slope(self):
        numerator = (self.end.y - self.start.y)
        return numerator / (self.end.x - self.start.x) if self.end.x != self.start.x else get_nan(numerator)

    @property
    def angle(self):
        radians = math.atan2(self.end.y - self.start.y, self.end.x - self.start.x)
        return math.degrees(radians)


class Waypoint:
    def __init__(self, x, y, index, prev_waypoint):
        self.x = x
        self.y = y
        self.index = index
        self.next_waypoint = None
        self.prev_waypoint = prev_waypoint

    def set_prev_waypoint(self, waypoint):
        self.prev_waypoint = waypoint

    def set_next_waypoint(self, waypoint):
        self.next_waypoint = waypoint


class TrackWaypoints:

    def __init__(self):
        self.waypoints = []
        self.waypoints_map = {}

    def create_waypoints(self, waypoints):
        for i, wp in enumerate(waypoints):
            prev_waypoint = self.waypoints[-1] if self.waypoints else None
            waypoint = Waypoint(wp[0], wp[1], i, prev_waypoint)

            if self.waypoints:
                self.waypoints[-1].set_next_waypoint(waypoint)

            self.waypoints.append(waypoint)
            self.waypoints_map[i] = waypoint
        self.waypoints[-1].set_next_waypoint(self.waypoints[0])
        self.waypoints[0].set_prev_waypoint(self.waypoints[-1])


class LinearWaypointSegment:

    def __init__(self, start, end, prev_segment):
        self.start = start
        self.end = end
        self.waypoints = [start, end]
        self.waypoint_indices = {start.index, end.index}
        self.prev_segment = prev_segment
        self.next_segment = None
        slope_numerator = (end.y - start.y)
        self.slope = slope_numerator / (end.x - start.x) if end.x != start.x else get_nan(slope_numerator)

    def add_waypoint(self, waypoint):
        self.end = waypoint
        self.waypoint_indices.add(waypoint.index)
        self.waypoints.append(waypoint)

    def set_next_segment(self, segment):
        self.next_segment = segment

    def set_prev_segment(self, segment):
        self.prev_segment = segment


    @property
    def angle(self):
        radians = math.atan2(self.end.y - self.start.y, self.end.x - self.start.x)
        return math.degrees(radians)

    @property
    def length(self):
        return math.sqrt((self.end.x - self.start.x) ** 2 + (self.end.y - self.start.y) ** 2)


# noinspection DuplicatedCode
class TrackSegments:
    def __init__(self):
        self.segments: list[LinearWaypointSegment] = []

    def add_waypoint_segment(self, start, end):
        radians = math.atan2(end.y - start.y, end.x - start.x)
        angle = math.degrees(radians)
        prev_segment = self.segments[-1] if self.segments else None

        if self.segments and abs(self.segments[-1].angle - angle) < segment_angle_threshold:
            self.segments[-1].add_waypoint(end)
        else:
            segment = LinearWaypointSegment(start, end, prev_segment)
            if self.segments:
                self.segments[-1].set_next_segment(segment)
            self.segments.append(segment)

    def create_segments(self, waypoints):
        for i in range(len(waypoints) - 1):
            start = waypoints[i]
            end = waypoints[i + 1]
            self.add_waypoint_segment(start, end)
        self.add_waypoint_segment(waypoints[-1], waypoints[0])
        self.segments[-1].set_next_segment(self.segments[0])
        self.segments[0].set_prev_segment(self.segments[-1])

    def upcoming_curve_factor(self, cawpi, waypoints, heading):
        segment = self.get_closest_segment_ahead(cawpi)
        next_segment = segment.next_segment
        next_segment_start = next_segment.start
        next_segment_distance = math.sqrt((next_segment_start.x - waypoints[cawpi][0]) ** 2 + (next_segment_start.y - waypoints[cawpi][1]) ** 2)

        max_curve_distance_factor = segment.length / (segment.length + next_segment.length)
        curve_distance_factor = next_segment_distance / (segment.length + next_segment.length)

        curve_distance_ratio = curve_distance_factor / max_curve_distance_factor

        max_angle_diff = 90
        angle_diff = min(abs(next_segment.next_segment.angle - heading), max_angle_diff)
        angle_diff_radians = math.radians(angle_diff)
        curve_factor = math.cos(angle_diff_radians)
        if curve_distance_ratio < curve_distance_ratio_threshold and angle_diff < curve_angle_threshold:
            return curve_factor
        else:
            return 1

    def get_closest_segment_ahead(self, closest_ahead_waypoint_index):
        closest_segment = None
        for segment in self.segments:
            if closest_ahead_waypoint_index in segment.waypoint_indices:
                closest_segment = segment
                break
        return closest_segment


track_segments = TrackSegments()
track_waypoints = TrackWaypoints()


def get_slope_intercept(x1, y1, m):
    return y1 - m * x1


class LinearFunction:
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
    def from_point_slope(cls, x1, y1, m):
        intercept = y1 - m * x1
        return cls(m, intercept, Point(x1, y1))

    @classmethod
    def get_perp_func(cls, x1, y1, slope):
        perp_slope = -1 / slope if slope != 0 else -slope
        perp_intercept = get_slope_intercept(x1, y1, perp_slope)
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
        else:
            self.prev_speed = None

    def _set_derived_inputs(self, fps):
        self.fps = fps
        self.progress_val = (self.progress / 100)
        self.speed_ratio = self.speed / max_speed
        self.heading360 = self.heading if self.heading >= 0 else 360 + self.heading
        self.abs_steering_angle = abs(self.steering_angle)
        self.x_velocity = self.speed * math.cos(math.radians(self.heading360))
        self.y_velocity = self.speed * math.sin(math.radians(self.heading360))
        self.next_x = self.x + self.x_velocity / self.fps
        self.next_y = self.y + self.y_velocity / self.fps
        self.closest_behind_waypoint_index = self.closest_waypoints[0]
        self.closest_ahead_waypoint_index = self.closest_waypoints[1]
        self.half_track_width = self.track_width / 2
        self.quarter_track_width = self.half_track_width / 2
        self.max_distance_traveled = self.steps * max_speed / self.fps
        self.max_progress_percentage = self.max_distance_traveled / self.track_length
        self.progress_percentage = self.progress / 100

    def _set_future_inputs(self):
        self.x_velocity = self.speed * math.cos(math.radians(self.heading360))
        self.y_velocity = self.speed * math.sin(math.radians(self.heading360))
        self.next_x = self.x + self.x_velocity / self.fps
        self.next_y = self.y + self.y_velocity / self.fps

    @property
    def reward(self):
        reward = self.speed_reward * self.progress_reward * (self.center_line_reward + self.waypoint_heading_reward + self.steering_reward) / 3
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
        segment = track_segments.get_closest_segment_ahead(self.closest_ahead_waypoint_index)
        pre_target_steering = self.heading360 - segment.angle
        self.target_steering_angle = min(abs_max_steering_angle, pre_target_steering) if pre_target_steering > 0 else max(-abs_max_steering_angle, pre_target_steering)
        abs_steering_diff = min(abs(self.target_steering_angle - self.steering_angle), 90)
        abs_target_steering_reward = math.cos(math.radians(self.target_steering_angle))
        on_target_steering_reward = math.cos(math.radians(abs_steering_diff))
        # We want to reward for both being on target and for requiring a small steering angle
        steering_reward = abs_target_steering_reward * on_target_steering_reward
        return steering_reward

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
        max_heading_error = 90
        next_track_wp = track_waypoints.waypoints_map[self.closest_ahead_waypoint_index]
        next_next_track_wp = next_track_wp.next_waypoint
        next_segment = LinearFunction.from_points(next_track_wp.x, next_track_wp.y, next_next_track_wp.x, next_next_track_wp.y)
        perp_waypoint_func = LinearFunction.get_perp_func(next_next_track_wp.x, next_next_track_wp.y, next_segment.slope)
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
        self.target_speed = min_speed + (max_speed - min_speed) * self.curve_factor
        reward = math.exp(-abs(self.speed - self.target_speed) / self.target_speed)
        # noinspection PyChainedComparisons
        if self.speed == self.target_speed:
            return reward
        elif self.prev_speed and self.prev_speed < self.speed and self.target_speed > self.speed and self.curve_factor >= 1:
            min_prev_speed = max(self.prev_speed, min_speed)
            max_speed_factor = (max_speed / min_prev_speed)
            prev_speed_factor = (self.speed / min_prev_speed)
            speed_factor = 1 + prev_speed_factor / max_speed_factor
            return reward * speed_factor / 2
        else:
            return reward / 2

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
        return track_segments.upcoming_curve_factor(self.closest_ahead_waypoint_index, self.waypoints, self.heading360)


class Simulation:

    def __init__(self):
        self.sim_state_initialized = False
        self.run_state = None
        self.track_time = True
        TIME_WINDOW = 10
        self.time = numpy.zeros([TIME_WINDOW, 2])
        self.total_frames = 0

    def set_sim_state(self, waypoints):
        track_waypoints.create_waypoints(waypoints)
        track_segments.create_segments(track_waypoints.waypoints)
        self.sim_state_initialized = True

    def add_run_state(self, params):
        steps = params['steps']
        if LOCAL_TRAINING:
            self.record_time(steps)
            self.rtf, self.fps, frames = self.get_time()
            self.total_frames += frames
            print("TIME: s: {}, rtf: {}, fps:{}, frames: {}".format(int(steps), round(self.rtf, 2), round(self.fps, 2), frames))
            run_state = RunState(params, self.run_state, self.fps)
        else:
            run_state = RunState(params, self.run_state, 15)

        self.run_state = run_state
        print(self.run_state.reward_data)

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


sim = Simulation()


# noinspection PyUnusedFunction
def reward_function(params):
    '''
    Example of penalize steering, which helps mitigate zig-zag behaviors
    '''
    if not sim.sim_state_initialized:
        sim.set_sim_state(params['waypoints'])

    sim.add_run_state(params)
    return sim.run_state.reward
