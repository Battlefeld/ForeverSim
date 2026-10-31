"""Write the equipment slot of every item the engine or cmangos knows, for build_dungeon_catalog.lua.

    python _dev/tools/item_slots.py --engine deps/engine/assets/database/db.json \
        [--cmangos <classic-db item_template or full dump .sql>] > item-slots.tsv

NorgannonDB names an item's class and subclass but not where it is worn; the loot list needs that when the client
cannot say yet (an item not in its cache). One line per item: id, tab, the slot as the client's tooltip names it
("Back", "Finger", "Two-Hand"). the engine's item database (MIT) first, cmangos classic-db (GPL-3.0) for the rest.
"""
import argparse
import json
import re
import sys

# the engine's ItemType (proto/common.proto); weapons and ranged items get their slot from NorgannonDB's subclass
ENGINE_TYPES = {1: 'Head', 2: 'Neck', 3: 'Shoulder', 4: 'Back', 5: 'Chest', 6: 'Wrist', 7: 'Hands', 8: 'Waist', 9: 'Legs',
             10: 'Feet', 11: 'Finger', 12: 'Trinket'}
# the client's InventoryType
INVENTORY = {1: 'Head', 2: 'Neck', 3: 'Shoulder', 5: 'Chest', 6: 'Waist', 7: 'Legs', 8: 'Feet', 9: 'Wrist', 10: 'Hands',
             11: 'Finger', 12: 'Trinket', 13: 'One-Hand', 14: 'Shield', 15: 'Ranged', 16: 'Back', 17: 'Two-Hand',
             20: 'Chest', 21: 'Main Hand', 22: 'Off Hand', 23: 'Held In Off-hand', 25: 'Thrown', 26: 'Ranged', 28: 'Relic'}


def cmangos_slots(path):
    """entry -> InventoryType from the item_template INSERTs of a classic-db dump."""
    out, cols = {}, None
    text = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'CREATE TABLE `item_template` \((.*?)\n\)', text, re.S)
    if m:
        cols = re.findall(r'^\s*`(\w+)`', m.group(1), re.M)
    if not cols:
        return out
    entry, inv = cols.index('entry'), cols.index('InventoryType')
    # values are numbers or quoted strings; a row ends with ')'
    value = r"(?:'(?:[^'\\]|\\.|'')*'|[^,()']+)"
    row = re.compile(r'\((' + value + r'(?:,' + value + r')*)\)')
    for ins in re.finditer(r'INSERT INTO `item_template` VALUES (.*?);\n', text, re.S):
        for r in row.finditer(ins.group(1)):
            fields = re.findall(value, r.group(1))
            if len(fields) > max(entry, inv):
                try:
                    out[int(fields[entry])] = int(fields[inv])
                except ValueError:
                    pass
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--engine', required=True)
    p.add_argument('--cmangos')
    a = p.parse_args()
    slots = {}
    if a.cmangos:
        for id, inv in cmangos_slots(a.cmangos).items():
            if inv in INVENTORY:
                slots[id] = INVENTORY[inv]
    for item in json.load(open(a.engine, encoding='utf-8'))['items']:
        if item.get('type') in ENGINE_TYPES:
            slots[item['id']] = ENGINE_TYPES[item['type']]
    for id in sorted(slots):
        sys.stdout.write(f'{id}\t{slots[id]}\n')
    print(f'{len(slots)} items with a slot', file=sys.stderr)


if __name__ == '__main__':
    main()
