#!/bin/bash

echo "========================================================="
echo " Starting Unified GHMWS Engine Pipeline (ECMWF & AIFS)"
echo "========================================================="

while true; do
    echo "--- Cycle Started at $(date) ---"

    # =========================================================
    # 1. ECMWF PIPELINE (Dynamic: 6Z/18Z -> 144h, 0Z/12Z -> 360h)
    # =========================================================
    python3.11 - "ECMWF" << 'EOF'
import os
import sys
from datetime import datetime, timedelta
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from ecmwf.opendata import Client
import earthkit.data

model_type = sys.argv[1]

# Compute closest operational runtime
now_utc = datetime.utcnow()
if now_utc.hour >= 20:
    init_date_dt = now_utc
    init_time = 12
elif now_utc.hour >= 14:
    init_date_dt = now_utc
    init_time = 6
elif now_utc.hour >= 8:
    init_date_dt = now_utc
    init_time = 0
elif now_utc.hour >= 2:
    init_date_dt = now_utc - timedelta(days=1)
    init_time = 18
else:
    init_date_dt = now_utc - timedelta(days=1)
    init_time = 12

# ECMWF specific conditional forecast length
if init_time in [6, 18]:
    forecast_hours = 144
else:
    forecast_hours = 360

init_date = init_date_dt.strftime("%Y-%m-%d")
date_folder = init_date_dt.strftime("%Y%m%d")
time_str = f"{init_time:02d}Z"

path = f"/Users/eknlau/VS_code/GHMWS/ensemble-track/wp/{model_type}/{date_folder}/{time_str}/"
if not os.path.exists(path):
    os.makedirs(path)

target_bufr = os.path.join(path, f"ifs-{init_date}-{time_str}.bufr")
csv_nwp = os.path.join(path, f"ifs-{init_date}-{time_str}-NWP.csv")
client_kwargs = {"source": "ecmwf", "model": "ifs"}
line_color, line_style = '#546e7a', '-'
title_prefix, title_color = "ECMWF", '#1a237e'
subtitle = f"{forecast_hours}-hour Forecast"

# Reverted strictly back to 240.png as requested
output_png = os.path.join(path, "240.png")
print(f"[{datetime.now()}] Processing {model_type} ({time_str}) for {forecast_hours} hours -> Saving to 240.png...")

try:
    client = Client(**client_kwargs)
    client.retrieve(date=init_date, time=init_time, type="tf", stream="enfo", step=forecast_hours, target=target_bufr)
except Exception as e:
    print(f"Data not ready or download failed for {model_type}: {e}")
    sys.exit(0)

ds = earthkit.data.from_source("file", target_bufr)
df = ds.to_pandas(
    columns=["stormIdentifier", "ensembleMemberNumber", "typicalDate", "typicalTime", 
             "year", "month", "day", "hour", "latitude", "longitude", "pressureReducedToMeanSeaLevel"],
    filters={"meteorologicalAttributeSignificance": 1}, required_columns=True
)
df = df.dropna(subset=['year', 'month', 'day', 'hour', 'longitude', 'latitude']).copy()

b_date = df['typicalDate'].astype(int).astype(str)
b_time = df['typicalTime'].astype(int).astype(str).str.zfill(4) 
df['base_dt'] = pd.to_datetime((b_date + b_time).str[:12], format='%Y%m%d%H%M')
df['valid_dt'] = pd.to_datetime(df[['year', 'month', 'day', 'hour']])
df['pressure'] = df['pressureReducedToMeanSeaLevel'] / 100.0
df = df.rename(columns={"stormIdentifier": "track", "ensembleMemberNumber": "sample", "longitude": "lon", "latitude": "lat"})

df_nwp = df[df['track'].astype(str).str.endswith('W', na=False)].copy()
df_nwp.to_csv(csv_nwp, index=False, encoding='utf-8-sig')

if df_nwp.empty:
    print(f"No tracks found for {model_type}.")
    sys.exit(0)

base_time_str = df_nwp['base_dt'].iloc[0].strftime('%Y-%m-%d %H:%MZ')

bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
colors = ['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080']
cmap = mcolors.ListedColormap(colors)
norm = mcolors.BoundaryNorm(bounds, cmap.N)

fig = plt.figure(figsize=(12, 9), dpi=120, facecolor='#ffffff')
ax = plt.axes(projection=ccrs.PlateCarree())
ax.set_extent([100, 180, 0, 60], crs=ccrs.PlateCarree())
ax.add_feature(cfeature.OCEAN, facecolor='#f9fbfc', zorder=0)
ax.add_feature(cfeature.LAND, facecolor='#f0f2f0', edgecolor='#bcbcbc', linewidth=0.5, zorder=1)
ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#454545', zorder=2)
ax.add_feature(cfeature.BORDERS, linestyle='-', linewidth=0.4, edgecolor='#95a5a6', zorder=2)

gl = ax.gridlines(draw_labels=True, linestyle=':', alpha=0.4, color='#7f8c8d', zorder=3)
gl.top_labels, gl.right_labels = False, False

for _, group in df_nwp.groupby(['track', 'sample']):
    ax.plot(group['lon'], group['lat'], color=line_color, linestyle=line_style, linewidth=0.5, alpha=0.3, transform=ccrs.PlateCarree(), zorder=4)

sc = ax.scatter(df_nwp['lon'], df_nwp['lat'], edgecolors=cmap(norm(df_nwp['pressure'])), facecolors='none', s=20, linewidths=1.2, alpha=0.9, transform=ccrs.PlateCarree(), zorder=5)

cbar = plt.colorbar(plt.cm.ScalarMappable(cmap=cmap, norm=norm), ax=ax, pad=0.03, fraction=0.04, aspect=30)
cbar.set_label('Minimum Sea Level Pressure (hPa)', fontsize=10, labelpad=10, fontweight='bold')

plt.title(f"{title_prefix} Ensemble Tracks - GHMWS", fontsize=16, fontweight='bold', pad=40, color=title_color)
plt.text(0.5, 1.05, subtitle, transform=ax.transAxes, ha='center', fontsize=13, fontweight='bold', color='#333333')
plt.text(0.5, 1.02, f"Initial Time: {base_time_str}", transform=ax.transAxes, ha='center', fontsize=11, color='#546e7a')

plt.savefig(output_png, bbox_inches='tight')
plt.close(fig)
print(f"Successfully generated {model_type} plot asset.")
EOF

    echo "---------------------------------------------------------"

    # =========================================================
    # 2. AIFS PIPELINE (Static: Always 360h)
    # =========================================================
    python3.11 - "AIFS" << 'EOF'
import os
import sys
from datetime import datetime, timedelta
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from ecmwf.opendata import Client
import earthkit.data

model_type = sys.argv[1]

# Compute closest operational runtime
now_utc = datetime.utcnow()
if now_utc.hour >= 20:
    init_date_dt = now_utc
    init_time = 12
elif now_utc.hour >= 14:
    init_date_dt = now_utc
    init_time = 6
elif now_utc.hour >= 8:
    init_date_dt = now_utc
    init_time = 0
elif now_utc.hour >= 2:
    init_date_dt = now_utc - timedelta(days=1)
    init_time = 18
else:
    init_date_dt = now_utc - timedelta(days=1)
    init_time = 12

# AIFS always uses 360 hours regardless of init_time
forecast_hours = 360

init_date = init_date_dt.strftime("%Y-%m-%d")
date_folder = init_date_dt.strftime("%Y%m%d")
time_str = f"{init_time:02d}Z"

path = f"/Users/eknlau/VS_code/GHMWS/ensemble-track/wp/{model_type}/{date_folder}/{time_str}/"
if not os.path.exists(path):
    os.makedirs(path)

target_bufr = os.path.join(path, f"aifs-{init_date}-{time_str}.bufr")
csv_nwp = os.path.join(path, f"aifs-{init_date}-{time_str}-NWP.csv")
client_kwargs = {"source": "ecmwf", "model": "aifs-ens"}
line_color, line_style = '#1e88e5', '--'
title_prefix, title_color = "AIFS", '#0d47a1'
subtitle = f"{forecast_hours}-hour Forecast (aifs-ens)"

# Reverted strictly back to 240.png as requested
output_png = os.path.join(path, "240.png")
print(f"[{datetime.now()}] Processing {model_type} ({time_str}) for {forecast_hours} hours -> Saving to 240.png...")

try:
    client = Client(**client_kwargs)
    client.retrieve(date=init_date, time=init_time, type="tf", stream="enfo", step=forecast_hours, target=target_bufr)
except Exception as e:
    print(f"Data not ready or download failed for {model_type}: {e}")
    sys.exit(0)

ds = earthkit.data.from_source("file", target_bufr)
df = ds.to_pandas(
    columns=["stormIdentifier", "ensembleMemberNumber", "typicalDate", "typicalTime", 
             "year", "month", "day", "hour", "latitude", "longitude", "pressureReducedToMeanSeaLevel"],
    filters={"meteorologicalAttributeSignificance": 1}, required_columns=True
)
df = df.dropna(subset=['year', 'month', 'day', 'hour', 'longitude', 'latitude']).copy()

b_date = df['typicalDate'].astype(int).astype(str)
b_time = df['typicalTime'].astype(int).astype(str).str.zfill(4) 
df['base_dt'] = pd.to_datetime((b_date + b_time).str[:12], format='%Y%m%d%H%M')
df['valid_dt'] = pd.to_datetime(df[['year', 'month', 'day', 'hour']])
df['pressure'] = df['pressureReducedToMeanSeaLevel'] / 100.0
df = df.rename(columns={"stormIdentifier": "track", "ensembleMemberNumber": "sample", "longitude": "lon", "latitude": "lat"})

df_nwp = df[df['track'].astype(str).str.endswith('W', na=False)].copy()
df_nwp.to_csv(csv_nwp, index=False, encoding='utf-8-sig')

if df_nwp.empty:
    print(f"No tracks found for {model_type}.")
    sys.exit(0)

base_time_str = df_nwp['base_dt'].iloc[0].strftime('%Y-%m-%d %H:%MZ')

bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
colors = ['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080']
cmap = mcolors.ListedColormap(colors)
norm = mcolors.BoundaryNorm(bounds, cmap.N)

fig = plt.figure(figsize=(12, 9), dpi=120, facecolor='#ffffff')
ax = plt.axes(projection=ccrs.PlateCarree())
ax.set_extent([100, 180, 0, 60], crs=ccrs.PlateCarree())
ax.add_feature(cfeature.OCEAN, facecolor='#f9fbfc', zorder=0)
ax.add_feature(cfeature.LAND, facecolor='#f0f2f0', edgecolor='#bcbcbc', linewidth=0.5, zorder=1)
ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#454545', zorder=2)
ax.add_feature(cfeature.BORDERS, linestyle='-', linewidth=0.4, edgecolor='#95a5a6', zorder=2)

gl = ax.gridlines(draw_labels=True, linestyle=':', alpha=0.4, color='#7f8c8d', zorder=3)
gl.top_labels, gl.right_labels = False, False

for _, group in df_nwp.groupby(['track', 'sample']):
    ax.plot(group['lon'], group['lat'], color=line_color, linestyle=line_style, linewidth=0.5, alpha=0.3, transform=ccrs.PlateCarree(), zorder=4)

sc = ax.scatter(df_nwp['lon'], df_nwp['lat'], edgecolors=cmap(norm(df_nwp['pressure'])), facecolors='none', s=20, linewidths=1.2, alpha=0.9, transform=ccrs.PlateCarree(), zorder=5)

cbar = plt.colorbar(plt.cm.ScalarMappable(cmap=cmap, norm=norm), ax=ax, pad=0.03, fraction=0.04, aspect=30)
cbar.set_label('Minimum Sea Level Pressure (hPa)', fontsize=10, labelpad=10, fontweight='bold')

plt.title(f"{title_prefix} Ensemble Tracks - GHMWS", fontsize=16, fontweight='bold', pad=40, color=title_color)
plt.text(0.5, 1.05, subtitle, transform=ax.transAxes, ha='center', fontsize=13, fontweight='bold', color='#333333')
plt.text(0.5, 1.02, f"Initial Time: {base_time_str}", transform=ax.transAxes, ha='center', fontsize=11, color='#546e7a')

plt.savefig(output_png, bbox_inches='tight')
plt.close(fig)
print(f"Successfully generated {model_type} plot asset.")
EOF

    git add .
    git commit -m "Update plots"
    git push origin main
    echo "========================================================="
    
    # =========================================================
    # DYNAMIC SLEEP CALCULATION (Snaps to 02, 08, 14, 20 UTC)
    # =========================================================
    CURRENT_HOUR=$(date -u +%-H)
    CURRENT_MIN=$(date -u +%-M)
    CURRENT_SEC=$(date -u +%-S)

    # Find the next target hour
    if [ $CURRENT_HOUR -lt 2 ]; then NEXT_TARGET=2
    elif [ $CURRENT_HOUR -lt 8 ]; then NEXT_TARGET=8
    elif [ $CURRENT_HOUR -lt 14 ]; then NEXT_TARGET=14
    elif [ $CURRENT_HOUR -lt 20 ]; then NEXT_TARGET=20
    else NEXT_TARGET=26 # 26 hours means 02:00Z tomorrow
    fi

    HOURS_TO_WAIT=$((NEXT_TARGET - CURRENT_HOUR - 1))
    MINS_TO_WAIT=$((59 - CURRENT_MIN))
    SECS_TO_WAIT=$((60 - CURRENT_SEC))

    TOTAL_SLEEP=$(( (HOURS_TO_WAIT * 3600) + (MINS_TO_WAIT * 60) + SECS_TO_WAIT ))

    echo "Cycle completed. Snapping to next target interval ($((NEXT_TARGET % 24)):00Z)."
    echo "Sleeping for $TOTAL_SLEEP seconds..."
    echo "========================================================="
    
    sleep $TOTAL_SLEEP
done