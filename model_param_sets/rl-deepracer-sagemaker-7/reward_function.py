import math


max_speed = 5
fps = 15
segment_angle_threshold = 5
distance_to_end_threshold = 2
min_speed = 0.5
curve_lookahead_segments = 2
curve_threshold = 40
curve_distance_ratio_threshold = 1 / 3
abs_max_steering_angle = 30


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

    def create_waypoints(self, waypoints):
        for i, wp in enumerate(waypoints):
            prev_waypoint = self.waypoints[-1] if self.waypoints else None
            waypoint = Waypoint(wp[0], wp[1], i, prev_waypoint)

            if self.waypoints:
                self.waypoints[-1].set_next_waypoint(waypoint)

            self.waypoints.append(waypoint)
        self.waypoints[-1].set_next_waypoint(self.waypoints[0])
        self.waypoints[0].set_prev_waypoint(self.waypoints[-1])

    def get_next_n_waypoints(self, waypoint, n):
        next_n_waypoints = []
        for i in range(n):
            next_waypoint = waypoint.next_waypoint
            next_n_waypoints.append(next_waypoint)
        return next_n_waypoints


class LinearSegment:

    def __init__(self, start, end, prev_segment):
        self.start = start
        self.end = end
        self.waypoints = [start, end]
        self.waypoint_indices = {start.index, end.index}
        self.prev_segment = prev_segment
        self.next_segment = None

    def add_waypoint(self, waypoint):
        self.end = waypoint
        self.waypoint_indices.add(waypoint.index)
        self.waypoints.append(waypoint)

    def set_next_segment(self, segment):
        self.next_segment = segment

    def set_prev_segment(self, segment):
        self.prev_segment = segment

    def distance_to_end(self, x, y):
        return math.sqrt((self.end.x - x) ** 2 + (self.end.y - y) ** 2)

    @property
    def angle(self):
        radians = math.atan2(self.end.y - self.start.y, self.end.x - self.start.x)
        return math.degrees(radians)

    @property
    def length(self):
        return math.sqrt((self.end.x - self.start.x) ** 2 + (self.end.y - self.start.y) ** 2)


track_waypoints = TrackWaypoints()


class TrackSegments:

    def __init__(self):
        self.segments = []

    def add_waypoint_segment(self, start, end):
        radians = math.atan2(end.y - start.y, end.x - start.x)
        angle = math.degrees(radians)
        prev_segment = self.segments[-1] if self.segments else None

        if self.segments and abs(self.segments[-1].angle - angle) < segment_angle_threshold:
            self.segments[-1].add_waypoint(end)
        else:
            segment = LinearSegment(start, end, prev_segment)
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

        max_angle_diff = 180
        angle_diff = abs(next_segment.next_segment.angle - heading)
        curve_factor = curve_distance_ratio * (1 - angle_diff / max_angle_diff)
        if curve_distance_ratio <= curve_distance_ratio_threshold and angle_diff <= curve_threshold:
            return curve_factor
        else:
            return 0

    def get_closest_segment_ahead(self, closest_ahead_waypoint_index):
        closest_segment = None
        for segment in self.segments:
            if closest_ahead_waypoint_index in segment.waypoint_indices:
                closest_segment = segment
                break
        return closest_segment

    def get_next_n_segments(self, segment, n):
        next_n_segments = []
        for i in range(n):
            next_segment = segment.next_segment
            next_n_segments.append(next_segment)
        return next_n_segments


track_segments = TrackSegments()


def center_line_reward(distance_from_center, track_width):
    half_track_width = track_width / 2
    quarter_track_width = half_track_width / 2
    min_distance_factor = quarter_track_width / half_track_width
    distance_factor = min(distance_from_center, quarter_track_width) / half_track_width
    bounded_distance_factor = min(1, distance_factor)
    return math.exp(-bounded_distance_factor)


def steering_reward(steering_angle, heading, closest_ahead_waypoint_index, curve_factor):
    max_angle_diff = 180
    segment = track_segments.get_closest_segment_ahead(closest_ahead_waypoint_index)
    heading360 = heading_to_360(heading)
    target_steering = heading360 - segment.angle
    target_steering = min(30, target_steering) if target_steering > 0 else max(-30, target_steering)
    steering_reward = math.exp(-abs(target_steering - steering_angle)) * (1 + curve_factor - abs(steering_angle) / abs_max_steering_angle)
    return steering_reward


def speed_reward(speed, waypoint_slope_val, curve_upcoming):
    if curve_upcoming:
        speed_factor = curve_upcoming * (speed - min_speed) / (max_speed - min_speed)
    else:
        speed_factor = (speed - min_speed) / (max_speed - min_speed)
    return speed_factor


def speed_penalty(x, y, closest_ahead_waypoint_index):
    segment = track_segments.get_closest_segment_ahead(closest_ahead_waypoint_index)
    if segment.distance_to_end(x, y) < distance_to_end_threshold:
        return 1
    else:
        return 0


def heading_to_360(heading):
    if heading < 0:
        return 360 + heading
    else:
        return heading


def waypoint_heading_reward(waypoints, closest_waypoints, heading):
    max_heading_error = 90
    x1, y1 = waypoints[closest_waypoints[0]]
    x2, y2 = waypoints[closest_waypoints[1]]
    xvec = x2 - x1
    yvec = y2 - y1
    waypoint_radians = math.atan2(yvec, xvec)
    waypoint_theta = math.degrees(waypoint_radians)
    heading360 = heading_to_360(heading)
    heading_error = abs(waypoint_theta - heading360)
    heading_factor = math.exp(-heading_error / max_heading_error)
    return heading_factor


def reward_function(params):
    '''
    Example of penalize steering, which helps mitigate zig-zag behaviors
    '''
    if not track_waypoints.waypoints:
        track_waypoints.create_waypoints(params['waypoints'])
    if not track_segments.segments:
        track_segments.create_segments(track_waypoints.waypoints)
        print(track_segments.segments)

    print(
        {
            'num_waypoints': len(track_waypoints.waypoints),
            'num_segments': len(track_segments.segments)
        })

    # Read input parameters
    x = params['x']
    y = params['y']
    all_wheels_on_track = params['all_wheels_on_track']
    is_crashed = params['is_crashed']
    is_left_of_center = params['is_left_of_center']
    is_offtrack = params['is_offtrack']
    track_width = params['track_width']
    track_length = params['track_length']
    steps = params['steps']
    speed = params['speed']

    progress = params['progress']
    heading = params['heading']
    heading360 = heading_to_360(heading)
    x_velocity = speed * math.cos(math.radians(heading360))
    y_velocity = speed * math.sin(math.radians(heading360))
    next_x = x + x_velocity / fps
    next_y = y + y_velocity / fps
    waypoints = params['waypoints']
    closest_behind_waypoint_index = params['closest_waypoints'][0]
    closest_ahead_waypoint_index = params['closest_waypoints'][1]
    closest_waypoints = (closest_behind_waypoint_index, closest_ahead_waypoint_index)
    steering_angle = params['steering_angle']
    distance_from_center = params['distance_from_center']

    curve_upcoming = track_segments.upcoming_curve_factor(closest_ahead_waypoint_index, waypoints, heading)
    center_line_val = center_line_reward(distance_from_center, track_width)
    waypoint_slope_val = waypoint_heading_reward(waypoints, closest_waypoints, heading)
    steering_val = steering_reward(steering_angle, heading, closest_ahead_waypoint_index, curve_upcoming)
    speed_val = speed_reward(speed, waypoint_slope_val, curve_upcoming)
    max_progress_val = ((steps * max_speed / fps) / track_length)
    progress_val = (progress / 100)
    progress_factor = progress_val / max_progress_val
    speed_factor = math.exp(speed_val - 1)
    reward = speed_factor * progress_val * (center_line_val + waypoint_slope_val + steering_val) / 3
    if all_wheels_on_track and not is_crashed:
        if is_offtrack:
            reward *= 0.01
    else:
        reward *= 1e-4
    return float(reward)
