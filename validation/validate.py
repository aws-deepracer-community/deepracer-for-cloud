from typing import Literal

from pydantic import conint, confloat, BaseModel


class HyperParameters(BaseModel):
    batch_size: Literal[32, 64, 128, 256, 512]
    discount_factor: confloat(ge=0, le=1)
    num_episodes_between_training: conint(ge=5, le=100)
    lr: confloat(ge=1e-8, le=0.001)
    num_epochs: conint(ge=3, le=10)
    entropy: confloat(ge=0, le=1)
    loss_type: Literal["huber", "mse"]

with open('../custom_files/hyperparameters.json', 'r') as f:
    hp = HyperParameters.model_validate_json(f.read())