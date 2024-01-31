import math


max_speed = 5
fps = 15


def center_line_reward(distance_from_center, track_width):
    half_track_width = track_width / 2
    distance_factor = distance_from_center / half_track_width
    bounded_distance_factor = min(1, distance_factor)
    return math.exp(-bounded_distance_factor)


def steering_reward(steering_angle):
    max_steering_angle = 30
    steering_factor = 1 - abs(steering_angle) / max_steering_angle
    return steering_factor


def speed_reward(speed, center_line_val):
    pre_calc_vals = center_line_val
    max_speed_factor = pre_calc_vals
    speed_factor = pre_calc_vals * (speed / max_speed)
    return speed_factor / max_speed_factor


def heading_to_360(heading):
    if heading < 0:
        return 360 + heading
    else:
        return heading


def waypoint_distance_reward(x, y, waypoints, closest_waypoints, center_line_val):
    x1, y1 = waypoints[closest_waypoints[0]]
    x2, y2 = waypoints[closest_waypoints[1]]
    max_xvec = x2 - x1
    max_yvec = y2 - y1
    xvec = x2 - x
    yvec = y2 - y
    max_distance_reward = math.sqrt(max_xvec ** 2 + max_yvec ** 2) / 2
    distance_reward_factor = math.sqrt(xvec ** 2 + yvec ** 2)
    reward = math.exp(-distance_reward_factor / max_distance_reward / center_line_val)
    return reward


def waypoint_slope_reward(waypoints, closest_waypoints, heading, center_line_val, waypoint_distance_val):
    max_heading_error = 360
    x1, y1 = waypoints[closest_waypoints[0]]
    x2, y2 = waypoints[closest_waypoints[1]]
    xvec = x2 - x1
    yvec = y2 - y1
    waypoint_radians = math.atan2(yvec, xvec)
    waypoint_theta = math.degrees(waypoint_radians)
    heading360 = heading_to_360(heading)
    heading_error = waypoint_theta - heading360
    heading_factor = math.exp(-abs(heading_error) * waypoint_distance_val / center_line_val / max_heading_error)
    return heading_factor


def reward_function(params):
    '''
    Example of penalize steering, which helps mitigate zig-zag behaviors
    '''

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
    waypoints = params['waypoints']
    closest_waypoints = params['closest_waypoints']
    steering_angle = params['steering_angle']
    distance_from_center = params['distance_from_center']
    center_line_val = center_line_reward(distance_from_center, track_width)
    steering_val = steering_reward(steering_angle)
    speed_val = speed_reward(speed, center_line_val)
    val_dict = {
        'center_line_val': center_line_val,

        'steering_val': steering_val,
        'speed_val': speed_val
    }

    reward = center_line_val * steering_val * speed_val
    if all_wheels_on_track and not is_crashed:
        if is_offtrack:
            reward *= 0.1
    else:
        reward *= 1e-3

    return float(reward)
