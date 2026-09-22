import csv,json,pathlib,statistics,math,collections,os
os.environ['MPLCONFIGDIR']='/private/tmp/biome-audit-20260917/mpl'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
B=pathlib.Path('/private/tmp/biome-audit-20260917')
OUT=pathlib.Path('/Users/skylartan/Desktop/BiomeBloome/docs/audits/2026-09-17/evidence')
seeds=[240817,9327,401,9031,17117]
scenarios=['A','B','C','D','E','F','E_open','F_pairs','B_rich','B_compact']
summary={}
for k in scenarios:
 ds=[json.loads(p.read_text()) for p in B.glob(k+'_[0-9]*.json')]
 if not ds:continue
 summary[k]={'n':len(ds),'end_r':[d['end_r'] for d in ds],'end_f':[d['end_f'] for d in ds],'peak_r':[d['peak_r'] for d in ds],'peak_f':[d['peak_f'] for d in ds],'extinction_r':[round(d['extinction_r'],1) for d in ds],'extinction_f':[round(d['extinction_f'],1) for d in ds],'events':{key:[d['events'][key] for d in ds] for key in ds[0]['events']},'seeds':[d['seed'] for d in ds]}
(OUT/'summary.json').write_text(json.dumps(summary,indent=2))
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False,'figure.facecolor':'#fcfcf7','axes.facecolor':'#fcfcf7'})
titles={'A':'A · Forage + 7 rabbits','B':'B · 24 rabbits + 2 foxes','C':'C · 24 rabbits + 10 foxes','D':'D · Weak forage, 24 rabbits + 2 foxes','E':'E · Forage + nearby thicket + predators','F':'F · Six isolated rabbits, radius 940','E_open':'E control · Same food, no thicket','F_pairs':'F control · Six rabbits in three pairs','B_rich':'B control · Twice as many food patches','B_compact':'B control · Richer, compact habitat'}
for tag,ks,shape in [('population_curves',scenarios[:6],(3,2)),('control_curves',scenarios[6:],(2,2))]:
 fig,axs=plt.subplots(*shape,figsize=(14,4*shape[0]),layout='constrained')
 for ax,k in zip(axs.flat,ks):
  allrows=[]
  for seed in seeds:
   f=B/f'{k}_{seed}.csv';jf=B/f'{k}_{seed}.json'
   if not f.exists() or not jf.exists():continue
   data=np.genfromtxt(f,delimiter=',',names=True);allrows.append(data)
   ax.plot(data['time']/60,data['rabbits'],color='#347950',alpha=.28,lw=.8)
   ax.plot(data['time']/60,data['foxes'],color='#ce652b',alpha=.38,lw=.8)
  if allrows:
   for species,color in [('rabbits','#286a42'),('foxes','#bf4e1b')]:
    ax.plot(allrows[0]['time']/60,np.median(np.vstack([d[species] for d in allrows]),axis=0),color=color,lw=2.1,label=species.title()+' median')
  ax.set_title(titles[k],loc='left',weight='bold');ax.set(xlim=(0,30),ylim=(0,None),xlabel='Simulation minutes',ylabel='Living individuals')
  ax.grid(axis='y',alpha=.18);ax.text(.98,.95,f'{len(allrows)} completed seeds',transform=ax.transAxes,ha='right',va='top',fontsize=9)
 axs.flat[0].legend(loc='upper left',frameon=False)
 fig.suptitle('Biome Bloom · unchanged simulation rules, normal aging, no ongoing supplies\nThin lines: individual seeds. Thick lines: median; no smoothing.',fontsize=13)
 fig.savefig(OUT/f'{tag}.png',dpi=150);fig.savefig(OUT/f'{tag}.svg');plt.close(fig)
fig,axs=plt.subplots(3,2,figsize=(14,10),layout='constrained')
for ax,k in zip(axs.flat,scenarios[:6]):
 for seed in seeds:
  f=B/f'{k}_{seed}.csv';jf=B/f'{k}_{seed}.json'
  if not f.exists() or not jf.exists():continue
  data=np.genfromtxt(f,delimiter=',',names=True)
  ax.plot(data['time']/60,data['stock_ratio'],alpha=.65,lw=1,label=str(seed))
 ax.set(title=titles[k],xlabel='Simulation minutes',ylabel='Biomass / capacity',xlim=(0,30),ylim=(0,1.02));ax.grid(alpha=.18)
axs.flat[0].legend(fontsize=8,frameon=False,ncol=2)
fig.suptitle('Resource pressure and recovery · remaining food stock by seed',fontsize=14)
fig.savefig(OUT/'resource_curves.png',dpi=150);plt.close(fig)
# Timeline and path of the compact-run focal animal. Incomplete final JSON lines are ignored.
frames=[]
for l in (B/'live/telemetry.jsonl').read_text().splitlines():
 try:f=json.loads(l)
 except json.JSONDecodeError:continue
 if f['t']<=120:
  a=next((a for a in f['animals'] if a['id']==f['watched']),None)
  if a:frames.append((f['t'],a))
colors={'eat':'#df6c2f','seek_food':'#266ead','loaf':'#79857c','socialize':'#895caf','wander':'#111111'}
fig,(ax,ay)=plt.subplots(1,2,figsize=(14,5),layout='constrained')
for state,color in colors.items():
 rows=[(t,a) for t,a in frames if a['behavior']==state]
 if not rows:continue
 ax.scatter([a['x'] for t,a in rows],[a['y'] for t,a in rows],s=7,c=color,label=state)
 ay.scatter([t for t,a in rows],[math.hypot(a['vx'],a['vy']) for t,a in rows],s=6,c=color,label=state)
ax.set(title='Dandelion · position samples',xlabel='World x',ylabel='World y');ax.invert_yaxis();ax.set_aspect('equal');ax.legend(frameon=False)
ay.set(title='“Eat” is still movement; “loaf” is seldom still',xlabel='Simulation seconds',ylabel='Speed (world units/s)');ay.axhline(38,color='#555',ls='--',lw=.7,label='Configured travel speed');ay.set_ylim(0,None)
fig.suptitle('Actual main-scene telemetry · compact opening, 120 simulation seconds\nSamples, not continuous occupancy estimates; no AI changes.',fontsize=12)
fig.savefig(OUT/'rabbit_motion.png',dpi=150);fig.savefig(OUT/'rabbit_motion.svg');plt.close(fig)
print(json.dumps(summary,indent=2))
