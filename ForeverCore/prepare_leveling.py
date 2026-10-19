"""Extract level 10-60 inputs from the same MythicSim snapshot and its client tables.

The engine overlay (engine-overlay/) turns this table into the engine's per-level base stats; the
level-60 row must equal upstream's own tables, which the overlay test checks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
from engine_source import verify_source

CLASSES = {1:'warrior', 2:'paladin', 3:'hunter', 4:'rogue', 5:'priest', 7:'shaman', 8:'mage', 9:'warlock', 11:'druid'}
STATS = {'0':'mana','1':'health','3':'agility','4':'strength','5':'intellect','6':'spirit','7':'stamina'}

def extract(engine, database, output):
    engine, database = Path(engine).resolve(), Path(database).resolve()
    lock = verify_source(engine)
    planner = engine / 'assets/db_inputs/wowhead_forever_gearplanner.txt'
    text = planner.read_text()
    match = re.search(r'WH\.setPageData\("wow\.gearPlanner\.classicplus\.baseStats",\s*', text)
    if not match:
        raise ValueError('Pinned gear-planner base stats missing')
    base = json.JSONDecoder().raw_decode(text[match.end():])[0]
    with sqlite3.connect('file:' + str(database) + '?mode=ro', uri=True) as conn:
        rows = conn.execute('SELECT ClassID, Level, BaseMana, CritPerAgility, SpellCritPerIntellect FROM PlayerExpectedStat WHERE ContentSetID=0 AND Level BETWEEN 10 AND 60').fetchall()
    expected = {}
    for cl, level, mana, agi, intellect in rows:
        if cl not in CLASSES:
            continue
        key = (cl, level)
        values = dict(mana=mana, critPerAgility=agi*100, critPerIntellect=intellect*100)
        if key in expected and expected[key] != values:
            raise ValueError('Conflicting client rows: ' + str(key))
        expected[key] = values
    classes = {}
    discrepancies = []
    for cl, name in CLASSES.items():
        levels = {}
        source = base['stats'][str(cl)]
        for level in range(10, 61):
            if (cl, level) not in expected:
                raise ValueError(f'Missing client level row: {name} {level}')
            values = {name:source[key][level] for key,name in STATS.items()}
            if values['mana'] != expected[(cl, level)]['mana']:
                discrepancies.append(dict(className=name, level=level, field='mana',
                                          planner=values['mana'], client=expected[(cl, level)]['mana']))
            # Same priority as upstream's level-60 generator: the client wins over planner mana.
            values.update(expected[(cl, level)])
            levels[str(level)] = values
        classes[name] = levels
    go = '''package main
import ("encoding/json";"os"; "github.com/wowsims/forever/sim/core/spelldata")
func main() {
 rows:=[]map[string]any{}
 for _,s:=range spelldata.All() {
  if s.ClassFlags.Family==0 || s.RankNumber()==0 {continue}
  rows=append(rows,map[string]any{"id":s.ID,"name":s.Name,"rank":s.RankNumber(),"learnLevel":s.BaseLevel,"spellLevel":s.SpellLevel,"maxLevel":s.MaxLevel,"family":s.ClassFlags.Family})
 }
 if e:=json.NewEncoder(os.Stdout).Encode(rows);e!=nil {panic(e)}
}
'''
    with tempfile.TemporaryDirectory(prefix='forevercore-level-data-') as temp:
        file = Path(temp)/'export.go'
        file.write_text(go)
        spells = json.loads(subprocess.check_output(['go','run',str(file)],cwd=engine))
    result = dict(schema=1, engineRevision=lock['buildIdentity'], clientBuild=lock['clientBuild'],
                  minLevel=10, maxLevel=60, simulationEnabled=True,
                  provenance=dict(plannerSHA256=hashlib.sha256(planner.read_bytes()).hexdigest(),
                                  clientTable='PlayerExpectedStat', clientDatabaseSHA256=hashlib.sha256(database.read_bytes()).hexdigest()),
                  classes=classes, rankedSpells=spells, sourceDiscrepancies=discrepancies)
    Path(output).write_text(json.dumps(result, separators=(',',':'))+'\n')
    print(f'{len(classes)} classes, {len(expected)} client rows, {len(spells)} ranked spells')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine',type=Path)
    parser.add_argument('client_database',type=Path)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    extract(args.engine,args.client_database,args.output)
