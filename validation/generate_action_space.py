import json


speeds = (1.4, 4.0)
angles = (-30, -20, -10, 0, 10, 20, 30)

action_space  = {
    'action_space': [
        {'steering_angle': steering_angle, 'speed': speed} for speed in speeds for steering_angle in angles if not (speed > 2 and abs(steering_angle) > 10)
    ]
}

with open('action_space.json', 'w') as f:
    json.dump(action_space, f, indent=2)
    print(json.dumps(action_space, indent=2))