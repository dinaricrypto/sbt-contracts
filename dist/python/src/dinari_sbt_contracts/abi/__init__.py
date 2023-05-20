import json
from importlib.resources import files


def get_abi(abi_name: str):
    source = files(__package__).joinpath(abi_name)
    return json.loads(source.read_text())
