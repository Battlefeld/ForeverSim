"""Import provisional food/recipe lists; never use recipe IDs as enchant effects.

Inputs are saved Wowhead HTML, per-item JSON tooltips from
https://nether.wowhead.com/tooltip/item/<id>?dataEnv=16&locale=0,
and the checkout pinned by engine.lock.json. No network access at runtime.
"""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path

FOOD_URL = 'https://www.wowhead.com/forever/news/all-cooking-food-that-currently-gives-xp-buffs-in-wow-forever-382928'
ENCHANT_URL = 'https://www.wowhead.com/forever/de/items/recipes/enchanting#0-4+20'
STATS = {'Strength': ['StatStrength'], 'Agility': ['StatAgility'],
         'Stamina': ['StatStamina'], 'Intellect': ['StatIntellect'],
         'Spirit': ['StatSpirit'], 'Attack Power': ['StatAttackPower', 'StatRangedAttackPower'],
         'Spell Damage': ['StatSpellDamage'], 'Healing Power': ['StatHealingPower'],
         'Armor': ['StatBonusArmor']}


def food_rows(text):
    marker = 'WH.markup.printHtml('
    markup = json.JSONDecoder().raw_decode(text.split(marker, 1)[1])[0]
    return re.findall(r'\[tr\]\[td\]\[item=(\d+)\]\[/td\]\[td\](\d+)\[/td\]\[td\]([^[]+)\[/td\]\[/tr\]', markup)


def recipe_rows(text):
    raw = text.split('var listviewitems = ', 1)[1].split(';\nnew Listview', 1)[0]
    # These two presentation-only JS properties are the only non-JSON fields.
    raw = re.sub(r'(?<=[{,])(firstseenpatch|popularity):', r'"\1":', raw)
    return json.loads(raw)


def food_entry(item_id, rows, tooltip):
    text = html.unescape(re.sub('<[^>]+>', ' ', tooltip.get('tooltip', '')))
    text = re.sub(r'\s+', ' ', text)
    level = re.search(r'Requires Level\s+(\d+)', text)
    entry = {'key': f'food:{item_id}', 'kind': 'food', 'itemId': item_id,
             'name': tooltip.get('name', f'Item {item_id}'), 'provisional': True,
             'source': FOOD_URL, 'minLevel': int(level[1]) if level else 1,
             'cookingSkill': min(int(r[1]) for r in rows),
             'articleClaims': sorted({r[2] for r in rows}), 'supported': False}
    match = re.search(r'well fed and gain\s+(.+?)\s+for\s+(\d+)\s+min', text)
    if not match:
        entry['reason'] = 'Buff-Werte im Item-Tooltip nicht eindeutig lesbar'
        return entry
    effect = match[1].strip()
    entry['effect'] = effect
    entry['duration'] = int(match[2]) * 60
    entry['xpKillPct'] = 5 if 'experience gained from kills is increased by 5%' in text else 0
    spells = re.findall(r'/forever/spell=(\d+)/nutritious-', tooltip.get('tooltip', ''))
    if spells:
        entry['spellId'] = int(spells[0])
    stat = re.fullmatch(r'\+?(\d+)\s+(.+)', effect)
    if stat and stat[2] in STATS:
        entry['stats'] = {key: int(stat[1]) for key in STATS[stat[2]]}
        entry['supported'] = True
    else:
        entry['reason'] = 'Effekt noch nicht eindeutig als Kampfwert zugeordnet (z. B. Krit-Art, Bewegung oder Beruf)'
    # The item tooltip wins over duplicates and incorrect classifications in the article.
    entry['valueSource'] = f'https://nether.wowhead.com/tooltip/item/{item_id}?dataEnv=16&locale=0'
    return entry


def generate(food_html, enchant_html, tooltip_dir, engine, lock):
    grouped = {}
    for row in food_rows(food_html):
        grouped.setdefault(int(row[0]), []).append(row)
    foods = []
    for item_id, rows in sorted(grouped.items()):
        path = tooltip_dir / f'tooltip-{item_id}.json'
        tooltip = json.loads(path.read_text()) if path.exists() else {}
        foods.append(food_entry(item_id, rows, tooltip))
    database_path = engine / 'assets/database/db.json'
    database = json.loads(database_path.read_text())
    by_recipe = {}
    for entry in database['enchants']:
        if entry.get('itemId'):
            by_recipe.setdefault(entry['itemId'], []).append(entry)
    enchants = []
    for recipe in recipe_rows(enchant_html):
        rid = recipe['id']
        matches = by_recipe.get(rid, [])
        if not matches:
            enchants.append({'key': f'recipe:{rid}', 'kind': 'enchant', 'itemId': rid,
                             'name': recipe['name'], 'skill': recipe.get('skill'),
                             'provisional': True, 'supported': False, 'source': ENCHANT_URL,
                             'reason': 'Rezept noch keiner Verzauberung der gepinnten Engine zugeordnet'})
        for entry in matches:
            # Store exact effect identity and restrictions, not a tooltip/stat approximation of procs.
            row = {k: v for k, v in entry.items() if k in ['effectId', 'spellId', 'itemId', 'type', 'extraTypes', 'enchantType', 'requiredProfession']}
            row.update(key=f"enchant:{rid}:{entry['effectId']}", kind='enchant',
                       name=recipe['name'].removeprefix('Formel: '), engineName=entry['name'],
                       skill=recipe.get('skill'), provisional=True, supported=True, source=ENCHANT_URL)
            enchants.append(row)
    # Minimal item geometry proves weapon/slot eligibility using the same pinned database as the engine.
    geometry = {str(i['id']): {k: i[k] for k in ['type', 'weaponType', 'handType', 'rangedWeaponType'] if k in i}
                for i in database['items']}
    corrections = json.loads(Path(__file__).with_name('enhancement-corrections.json').read_text())
    for row in foods:
        skill = corrections['foodCookingSkill'].get(str(row['itemId']))
        if skill is not None:
            row['cookingSkill'] = skill
            row['cookingSkillSource'] = corrections['source']
    return {'schema': 1, 'asOf': corrections['asOf'], 'upstreamRevision': lock['commit'],
            'databaseSHA256': hashlib.sha256(database_path.read_bytes()).hexdigest(),
            'sources': [{'kind': 'food', 'url': FOOD_URL}, {'kind': 'enchant', 'url': ENCHANT_URL}],
            'entries': foods + enchants, 'itemGeometry': geometry,
            'engineEnchants': {str(e['effectId']): e['name'] for e in database['enchants']}}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--food-html', required=True, type=Path)
    p.add_argument('--enchant-html', required=True, type=Path)
    p.add_argument('--tooltip-dir', required=True, type=Path)
    p.add_argument('--engine-source', required=True, type=Path)
    p.add_argument('--output', type=Path, default=Path(__file__).with_name('enhancements-data.json'))
    args = p.parse_args()
    lock = json.loads(Path(__file__).with_name('engine.lock.json').read_text())
    result = generate(args.food_html.read_text(), args.enchant_html.read_text(), args.tooltip_dir, args.engine_source, lock)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
