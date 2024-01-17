from enum import Enum

from pydantic import BaseModel, confloat, conint
from typing import Literal, Tuple

GLOBAL_MAX_SPEED = 4.0
GLOBAL_MIN_SPEED = 0.5
GLOBAL_ABS_MAX_STEERING_ANGLE = 30


class NeuralNetwork(Enum):
    """Enum containing the keys for neural networks"""
    DEEP_CONVOLUTIONAL_NETWORK_SHALLOW = 'DEEP_CONVOLUTIONAL_NETWORK_SHALLOW'
    DEEP_CONVOLUTIONAL_NETWORK = 'DEEP_CONVOLUTIONAL_NETWORK'
    DEEP_CONVOLUTIONAL_NETWORK_DEEP = 'DEEP_CONVOLUTIONAL_NETWORK_DEEP'


class ActionSpaceType(Enum):
    """Enum containing the keys for action space types"""
    DISCRETE = 'discrete'
    CONTINUOUS = 'continuous'


class TrainingAlgorithm(Enum):
    """Enum containing the keys for training algorithms"""
    PPO = 'clipped_ppo'
    SAC = 'sac'


class ContinuousActionSpaceSpeed(BaseModel):
    high: confloat(gt=GLOBAL_MIN_SPEED, le=GLOBAL_MAX_SPEED)
    low: confloat(ge=GLOBAL_MIN_SPEED, lt=GLOBAL_MAX_SPEED)


class ContinuousActionSpaceSteeringAngle(BaseModel):
    high: conint(gt=-GLOBAL_ABS_MAX_STEERING_ANGLE, le=GLOBAL_ABS_MAX_STEERING_ANGLE)
    low: conint(ge=-GLOBAL_ABS_MAX_STEERING_ANGLE, lt=GLOBAL_ABS_MAX_STEERING_ANGLE)

    @property
    def abs_max(self):
        return max(abs(self.high), abs(self.low))


class ContinuousActionSpace(BaseModel):
    speed: ContinuousActionSpaceSpeed
    steering_angle: ContinuousActionSpaceSteeringAngle


class ModelMetadata(BaseModel):
    action_space: ContinuousActionSpace
    neural_network: NeuralNetwork = NeuralNetwork.DEEP_CONVOLUTIONAL_NETWORK_SHALLOW
    action_space_type: ActionSpaceType = ActionSpaceType.CONTINUOUS
    training_algorithm: TrainingAlgorithm = TrainingAlgorithm.PPO
    sensor: Tuple[str] = "FRONT_FACING_CAMERA"
    version: str = "5"


class HyperParameters(BaseModel):
    batch_size: Literal[32, 64, 128, 256, 512]
    discount_factor: confloat(ge=0, le=1)
    num_episodes_between_training: conint(ge=5, le=100)
    lr: confloat(ge=1e-8, le=0.001)
    num_epochs: conint(ge=3, le=10)
    beta_entropy: confloat(ge=0, le=1)
    loss_type: Literal["huber", "mse"]


with open('custom_files/model_metadata.json', 'r') as f:
    mm = ModelMetadata.model_validate_json(f.read())

with open('custom_files/hyperparameters.json', 'r') as f:
    hp = HyperParameters.model_validate_json(f.read())

def get_updated_line(line):
    if 'MAX_SPEED =' in line:
        return f'MAX_SPEED = {mm.action_space.speed.high}\n'
    elif 'MIN_SPEED =' in line:
        return f'MIN_SPEED = {mm.action_space.speed.low}\n'
    elif 'ABS_MAX_STEERING_ANGLE =' in line:
        return f'ABS_MAX_STEERING_ANGLE = {mm.action_space.steering_angle.abs_max}\n'
    else:
        return line


with open('custom_files/reward_function.py', 'r') as f:
    nlines = []
    flines = f.readlines()
    for line in flines:
        nlines.append(get_updated_line(line))

with open('custom_files/reward_function.py', 'w') as f:
    f.writelines(nlines)

with open('system.env', 'r') as f:
    pass

with open('run.env', 'r') as f:
    nlines = []
    flines = f.readlines()
    for line in flines:
        pass