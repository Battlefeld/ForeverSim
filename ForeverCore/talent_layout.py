"""Source-derived talent geometry for the addon editor; no combat rules are changed."""
import argparse
import json
from pathlib import Path


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + json.dumps(k) + ']=' + lua(v) for k, v in sorted(value.items())) + '}'
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    return json.dumps(value, ensure_ascii=False)


def render(manifest):
    classes = {}
    for cl, profile in manifest['classes'].items():
        trees = []
        for tree in profile['trees']:
            nodes = []
            for node in tree['talents']:
                loc = node['location']
                row = dict(key=node['fieldName'], fieldName=node['fieldName'], spellId=node['spellId'],
                           row=loc['rowIdx'], column=loc['colIdx'], maxRank=node['maxPoints'])
                if node.get('prereqLocation'):
                    pre = node['prereqLocation']
                    row.update(preRow=pre['rowIdx'], preCol=pre['colIdx'])
                nodes.append(row)
            trees.append(dict(name=tree['name'], talents=nodes))
        classes[cl] = dict(talentTrees=trees)
    return '-- Generated from the pinned engine manifest by ForeverCore/talent_layout.py.\nForeverSimTalentData=' + lua(classes) + '\n'


def write(manifest, output):
    Path(output).write_text(render(manifest), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    write(json.loads(args.manifest.read_text()), args.output)
