#!/bin/bash

echo "========================================================="
echo " Starting Unified GHMWS Engine (IFS, AIFS, GEFS, AIGEFS)"
echo "========================================================="

while true; do
    echo "--- Cycle Started at $(date) ---"

    # We call python directly via a Here-Doc block, feeding the model string sequentially
    for MODEL in "ECMWF" "AIFS" "GEFS" "AIGEFS"; do
        
        python3.11 - "$MODEL" << 'EOF'
import os
import sys
import numpy as np
import pandas as pd
import requests
import xarray as xr
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature

model_type = sys.argv[1]
now_utc = datetime.utcnow()

# 1. TIMING ENGINE
if now_utc.hour >= 21: init_date_dt, init_time = now_utc, 12
elif now_utc.hour >= 15: init_date_dt, init_time = now_utc, 6
elif now_utc.hour >= 9: init_date_dt, init_time = now_utc, 0
elif now_utc.hour >= 3: init_date_dt, init_time = now_utc - timedelta(days=1), 18
else: init_date_dt, init_time = now_utc - timedelta(days=1), 12

init_date = init_date_dt.strftime("%Y-%m-%d")
date_folder = init_date_dt.strftime("%Y%m%d")
cycle_str = f"{init_time:02d}"

path = f"/Users/eknlau/VS_code/GHMWS/ensemble-track/wp/{model_type}/{date_folder}/{cycle_str}Z/"
os.makedirs(path, exist_ok=True)

# 2. DATA INGESTION ENGINE (ECMWF vs. NOAA Direct URLs)
df_nwp = pd.DataFrame()

if model_type in ["ECMWF", "AIFS"]:
    from ecmwf.opendata import Client
    import earthkit.data
    
    is_ifs = (model_type == "ECMWF")
    target_bufr = os.path.join(path, f"{model_type.lower()}-{init_date}-{cycle_str}Z.bufr")
    forecast_step = 144 if (is_ifs and init_time in [6, 18]) else 360
    subtitle = f"{forecast_step}-hour Forecast" if is_ifs else "360-hour Forecast (aifs-ens)"
    
    print(f"[{datetime.now()}] Fetching {model_type} via OpenData Client...")
    try:
        client = Client(source="ecmwf", model="ifs" if is_ifs else "aifs-ens")
        client.retrieve(date=init_date, time=init_time, type="tf", stream="enfo", step=forecast_step, target=target_bufr)
        ds = earthkit.data.from_source("file", target_bufr)
        df = ds.to_pandas(columns=["stormIdentifier", "ensembleMemberNumber", "pressureReducedToMeanSeaLevel", "longitude", "latitude"], 
                          filters={"meteorologicalAttributeSignificance": 1}).dropna()
        df_nwp = df[df['stormIdentifier'].astype(str).str.endswith('W', na=False)].copy()
        df_nwp = df_nwp.rename(columns={"stormIdentifier": "track", "ensembleMemberNumber": "sample", "longitude": "lon", "latitude": "lat"})
        df_nwp['pressure'] = df_nwp['pressureReducedToMeanSeaLevel'] / 100.0
    except Exception as e:
        print(f"Skipping {model_type}: Data not ready or failed: {e}")

elif model_type in ["GEFS", "AIGEFS"]:
    subtitle = "240-hour Forecast" if model_type == "GEFS" else "240-hour Forecast (AI)"
    base_urls = {
        "GEFS": f"https://noaa-gefs-pds.s3.amazonaws.com/gefs.{date_folder}/{cycle_str}/atmos/pgrb2ap5/",
        "AIGEFS": f"https://noaa-nws-graphcastgfs-pds.s3.amazonaws.com/EAGLE_ensemble/aigefs.{date_folder}/{cycle_str}/"
    }

    def fetch_noaa_member(member):
        mem_tracks = []
        for fxx in range(0, 241, 12):
            local_grib = os.path.join(path, f"temp_{model_type}_m{member:02d}_f{fxx:03d}.grib2")
            
            if model_type == "GEFS":
                url = base_urls["GEFS"] + f"gep{member:02d}.t{cycle_str}z.pgrb2a.0p50.f{fxx:03d}"
            else:
                url = base_urls["AIGEFS"] + f"mem{member:03d}/model/atmos/grib2/aigefs.t{cycle_str}z.sfc.f{fxx:03d}.grib2"
                
            try:
                r = requests.get(url, stream=True, timeout=10)
                if r.status_code != 200: continue
                with open(local_grib, 'wb') as f: f.write(r.content)
                
                # Extract MSLP low center coordinates from GRIB file
                ds = xr.open_dataset(local_grib, engine="cfgrib", filter_by_keys={'shortName': 'prmsl'})
                subset = ds.where((ds.longitude >= 100) & (ds.longitude <= 180) & (ds.latitude >= 0) & (ds.latitude <= 60), drop=True)
                p_matrix = subset.prmsl.values / 100.0
                min_idx = np.unravel_index(np.nanargmin(p_matrix), p_matrix.shape)
                
                if p_matrix[min_idx] < 1005.0:
                    lon = subset.longitude.values[min_idx[1]] if len(subset.longitude.shape) == 1 else subset.longitude.values[min_idx]
                    lat = subset.latitude.values[min_idx[0]] if len(subset.latitude.shape) == 1 else subset.latitude.values[min_idx]
                    mem_tracks.append({"track": f"Invest_{model_type}", "sample": member, "lon": float(lon), "lat": float(lat), "pressure": p_matrix[min_idx]})
                os.remove(local_grib)
            except:
                if os.path.exists(local_grib): os.remove(local_grib)
                continue
        return mem_tracks

    print(f"[{datetime.now()}] Direct scraping {model_type} server endpoints in parallel...")
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = executor.map(fetch_noaa_member, range(1, 31))
    
    flat_list = [item for sublist in results for item in sublist]
    df_nwp = pd.DataFrame(flat_list)

# 3. PLOTTING CORE ENGINE
if df_nwp.empty:
    print(f"No operational tracks found for {model_type}. Skipping asset rendering.")
else:
    df_nwp.to_csv(os.path.join(path, f"{model_type.lower()}-NWP.csv"), index=False)
    
    fig, ax = plt.subplots(figsize=(12, 9), dpi=120, subplot_kw={'projection': ccrs.PlateCarree()})
    ax.set_extent([100, 180, 0, 60])
    ax.add_feature(cfeature.LAND, facecolor='#f0f2f0', edgecolor='#bcbcbc')
    ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#454545')
    
    style_map = {
        "ECMWF": ('#546e7a', '-'), "AIFS": ('#1e88e5', '--'),
        "GEFS": ('#43a047', '-'), "AIGEFS": ('#e040fb', '--')
    }
    line_color, line_style = style_map[model_type]
    
    bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
    cmap = mcolors.ListedColormap(['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080'])
    norm = mcolors.BoundaryNorm(bounds, cmap.N)
    
    for _, group in df_nwp.groupby('sample'):
        ax.plot(group['lon'], group['lat'], color=line_color, linestyle=line_style, linewidth=0.6, alpha=0.4)
    ax.scatter(df_nwp['lon'], df_nwp['lat'], edgecolors=cmap(norm(df_nwp['pressure'])), facecolors='none', s=20)
    
    plt.colorbar(plt.cm.ScalarMappable(cmap=cmap, norm=norm), ax=ax, pad=0.03, fraction=0.04, aspect=30).set_label('MSLP (hPa)')
    plt.title(f"{model_type} Ensemble Tracks - GHMWS", fontsize=16, fontweight='bold')
    plt.text(0.5, 1.02, subtitle, transform=ax.transAxes, ha='center', fontsize=12)
    
    plt.savefig(os.path.join(path, "240.png"), bbox_inches='tight')
    plt.close(fig)
    print(f"Successfully processed and plotted {model_type} matrix items.")
EOF

    done

    # 4. GITHUB REPOSITORY SYNC
    echo "Synchronizing generated data maps to GitHub..."
    git add .
    git commit -m "Update full ensemble track suite (IFS, AIFS, GEFS, AIGEFS)"
    git push origin main
    
    echo "========================================================="
    echo "Pipeline complete. Sleeping for 6 hours..."
    echo "========================================================="
    sleep 21600
done