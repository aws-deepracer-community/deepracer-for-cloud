def reward_function(params):
    '''
    Reward function that considers both distance from center line and maintaining a moderate speed.
    '''
    
    distance_from_center = params['distance_from_center']
    track_width = params['track_width']
    steering = abs(params['steering_angle']) e
    speed = params['speed']

    marker_1 = 0.1 * track_width
    marker_2 = 0.25 * track_width
    marker_3 = 0.5 * track_width

    if distance_from_center <= marker_1:
        reward = 1.0
    elif distance_from_center <= marker_2:
        reward = 0.5
    elif distance_from_center <= marker_3:
        reward = 0.1
    else:
        reward = 1e-3 

    ABS_STEERING_THRESHOLD = 15

    if steering > ABS_STEERING_THRESHOLD:
        reward *= 0.8

    SPEED_MIN = 1.5
    SPEED_MAX = 2.5

    if SPEED_MIN <= speed <= SPEED_MAX:
        reward += 0.5 

    return float(reward)
