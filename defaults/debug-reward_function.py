import math
import numpy
import rospy
import time

class Reward:

    '''
    Debugging reward function to be used to track performance of local training.
    Will print out the Real-Time-Factor (RTF), as well as how many 
    steps-per-second (sim-time) that the system is able to deliver.
    '''

    def __init__(self, verbose=False, track_time=False):
        self.verbose = verbose
        self.track_time = track_time

        if track_time:
            TIME_WINDOW=10
            self.time = numpy.zeros([TIME_WINDOW, 2])

        if verbose:
            print("Initializing Reward Class")

    def get_time(self):

        wall_time_incr = numpy.max(self.time[:,0]) - numpy.min(self.time[:,0])
        sim_time_incr = numpy.max(self.time[:,1]) - numpy.min(self.time[:,1])
        
        rtf = sim_time_incr / wall_time_incr
        fps = (self.time.shape[0] - 1) / sim_time_incr

        return rtf, fps
    
    def record_time(self, steps):

        index = int(steps) % self.time.shape[0]
        self.time[index,0] = time.time()
        self.time[index,1] = rospy.get_time()

    def reward_function(self, params):

        # Read input parameters
        steps = params["steps"]

        if self.track_time:
            self.record_time(steps)

        if self.track_time:
            if steps >= self.time.shape[0]:
                rtf, fps = self.get_time()
                print("TIME: s: {}, rtf: {}, fps:{}".format(int(steps), round(rtf, 2), round(fps, 2) ))

        return 1.0


reward_object = Reward(verbose=False, track_time=True)

def reward_function(params):
    return reward_object.reward_function(params)
