from importlib.resources import files

def get_bin(bin_name: str):
    source = files(__package__).joinpath(bin_name)
    return f"0x{source.read_text()}"
