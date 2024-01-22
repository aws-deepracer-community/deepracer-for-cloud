from hypothesis import strategies as st
st.floats()
st.integers()

all_wheels_on_track = st.booleans()
num_waypoints = st.integers(min_value=2)

def get_waypoints(num_waypoints):
    return st.lists(st.tuples(st.floats(), st.floats()), min_size=num_waypoints, max_size=num_waypoints)

def get_closest_waypoints(num_waypoints):
    return st.lists(st.tuples(st.integers(), st.integers()), min_size=2, max_size=2)

def run_test(
    all_wheels_on_track,
    num_waypoints,
    closest_waypoints
):
    print(all_wheels_on_track, num_waypoints, closest_waypoints)