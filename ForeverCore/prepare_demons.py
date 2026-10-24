"""Voidwalker values per level for ForeverCore's synthetic kill profile (warlock-demons.json).

Without live data from the addon the engine gives demons their level 60 values. The kill profile of a synthetic
warlock instead passes the voidwalker of the character's level, from the cmangos classic-db dump (GPL-3.0):
pet_levelstats for the attributes and the melee damage as mangos-classic computes it for summoned pets
(Pet::InitStatsForLevel, SUMMON_PET: creature_template_classlevelstats with the demon's damage variance,
attack time and multiplier; maximum = 1.5 x minimum).

Usage: python3 -I prepare_demons.py ClassicDB_1_12_1_z2815.sql warlock-demons.json
"""
import re,sys,json
sql=open(sys.argv[1],encoding='utf-8',errors='replace').read()
def cols(t):
    m=re.search(r"CREATE TABLE `%s` \((.*?)\n\) ENGINE"%t,sql,re.S)
    return [c for c in re.findall(r"^\s+`(\w+)`",m.group(1),re.M)]
def rows(t):
    out=[]
    for m in re.finditer(r"INSERT INTO `%s` VALUES (.*?);\n"%t,sql,re.S):
        s=m.group(1); i=0; n=len(s)
        while i<n:
            if s[i]=='(':
                i+=1; row=[]; cur=''; q=False
                while True:
                    ch=s[i]
                    if q:
                        if ch=='\\': cur+=s[i+1]; i+=2; continue
                        if ch=="'": q=False
                        else: cur+=ch
                    elif ch=="'": q=True
                    elif ch==',': row.append(cur); cur=''
                    elif ch==')': row.append(cur); break
                    else: cur+=ch
                    i+=1
                out.append(row)
            i+=1
    return out
ct=cols('creature_template'); 
tmpl={int(r[0]):dict(zip(ct,r)) for r in rows('creature_template') if int(r[0]) in (1860,416,1863,417)}
cls={(int(r[0]),int(r[1])):dict(zip(cols('creature_template_classlevelstats'),r)) for r in rows('creature_template_classlevelstats')}
pls={}
for r in rows('pet_levelstats'):
    d=dict(zip(cols('pet_levelstats'),r))
    pls.setdefault(int(d['creature_entry']),{})[int(d['level'])]=d
for e,t in tmpl.items():
    print(e,t['Name'],t['UnitClass'],t['DamageVariance'],t['DamageMultiplier'],t['MeleeBaseAttackTime'],len(pls.get(e,{})))
vw=tmpl[1860]; uc=int(vw['UnitClass'])
out={}
for lvl in range(10,61):
    p=pls[1860][lvl]; c=cls[(lvl,uc)]
    mn=(float(c['BaseDamageExp0'])*float(vw['DamageVariance'])+float(c['BaseMeleeAttackPower'])/14*int(vw['MeleeBaseAttackTime'])/1000)*float(vw['DamageMultiplier'])
    out[str(lvl)]={"strength":int(p['str']),"agility":int(p['agi']),"stamina":int(p['sta']),"intellect":int(p['inte']),"spirit":int(p['spi']),"mana":int(p['mana']),"meleeMin":round(mn,2),"meleeMax":round(mn*1.5,2)}
print(out['10'],out['20'],out['30'],out['60'])
json.dump({"schema":"forevercore.demons.v1","source":"cmangos classic-db (GPL-3.0) pet_levelstats, creature_template 1860, creature_template_classlevelstats; Schaden nach mangos-classic Pet::InitStatsForLevel (SUMMON_PET)","voidwalker":out},open(sys.argv[2],'w'),indent=1)
