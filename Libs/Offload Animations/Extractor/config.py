# Constants
TICKS = 20
CHUNK_SIZE = 100 
PRECISION = 1000

# File Paths
MODEL_PATH = "model.bbmodel"
OUT_DIR = "animations/"

# Mappings
PART_MAP = {
    'player1': {'root': 'root', 'head': 'Head', 'body': 'Body', 'leftArm': 'LeftArm', 'rightArm': 'RightArm', 'leftLeg': 'LeftLeg', 'rightLeg': 'RightLeg'},
    'player2': {'root': 'P2root', 'head': 'P2Head', 'body': 'P2Body', 'leftArm': 'P2LeftArm', 'rightArm': 'P2RightArm', 'leftLeg': 'P2LeftLeg', 'rightLeg': 'P2RightLeg'}
}

# Settings to extract
SETTINGS = ['overrideVanilla', 'lockMovement', 'useCamera']
CAMERAS = {'shared': 'sharedCamera', 'player1': 'P1Camera', 'player2': 'P2Camera'}

# Helper to get global IDs
def get_part_ids():
    parts = sorted({p for role in PART_MAP.values() for p in role.keys()})
    return {p: i + 1 for i, p in enumerate(parts)}