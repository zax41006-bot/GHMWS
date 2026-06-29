#!/bin/bash

WORKSPACE="/Users/eknlau/VS_code/GHMWS/ensemble-track"
cd "$WORKSPACE"

echo "========================================================="
echo " Starting Google Weather Lab Live CSV Ingestion Engine"
echo "========================================================="

while true; do
    echo "--- Cycle Sync Attempt Started at $(date) ---"

    python3.11 << 'EOF'
import os
import requests
import pandas as pd
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature

base_path = "/Users/eknlau/VS_code/GHMWS/ensemble-track/wp"

# 1. CYCLICAL TIMING MATRIX
now_utc = datetime.utcnow()
if now_utc.hour >= 21: init_date_dt, init_time = now_utc, 12
elif now_utc.hour >= 15: init_date_dt, init_time = now_utc, 6
elif now_utc.hour >= 9: init_date_dt, init_time = now_utc, 0
elif now_utc.hour >= 3: init_date_dt, init_time = now_utc - timedelta(days=1), 18
else: init_date_dt, init_time = now_utc - timedelta(days=1), 12

yyyy = init_date_dt.strftime("%Y")
mm = init_date_dt.strftime("%m")
dd = init_date_dt.strftime("%d")
date_folder = f"{yyyy}{mm}{dd}"
cycle_str = f"{init_time:02d}Z"
time_stamp_str = f"{yyyy}_{mm}_{dd}T{init_time:02d}_00"

# Configuration setup for GENC and FNV3 configurations
models = {
    "GENC": {
        "line_color": "#009688", 
        "line_style": "--", 
        "title": "Google Weather Lab GENC Unpaired Ensemble"
    },
    "FNV3": {
        "line_color": "#ff5722", 
        "line_style": "-", 
        "title": "Google Weather Lab FNV3 Ensemble Tracks"
    }
}

# Unified Pressure Mapping Matrix
bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
cmap = mcolors.ListedColormap(['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080'])
norm = mcolors.BoundaryNorm(bounds, cmap.N)

for model_name, cfg in models.items():
    model_dir = os.path.join(base_path, model_name, date_folder, cycle_str)
    os.makedirs(model_dir, exist_ok=True)
    
    local_csv_path = os.path.join(model_dir, f"{model_name.lower()}-unpaired-NWP.csv")
    output_png = os.path.join(model_dir, "240.png")
    
    # 2. TARGET DIRECT URL ASSEMBLY 
    target_url = f"https://deepmind.google.com/science/weatherlab/download/cyclones/{model_name}/ensemble/cyclogenesis/csv/{model_name}_{time_stamp_str}_cyclogenesis.csv"
    
    print(f"[{datetime.now()}] Pulling {model_name} track matrix fields...")
    print(f"Target: {target_url}")
    
    try:
        r = requests.get(target_url, timeout=15)
        if r.status_code != 200:
            print(f"--> File unavailable on DeepMind host (HTTP {r.status_code}). Skipping {model_name}.")
            continue
            
        with open(local_csv_path, 'wb') as f:
            f.write(r.content)
            
        df = pd.read_csv(local_csv_path)
        if df.empty:
            print(f"--> Document downloaded for {model_name} contains no rows.")
            continue
            
        # Standardize structural headers across variants
        if 'member' in df.columns: df = df.rename(columns={'member': 'sample'})
        if 'lead_time' in df.columns: df = df.rename(columns={'lead_time': 'fxx'})
        if 'mslp' in df.columns: df = df.rename(columns={'mslp': 'pressure'})
        
        # 3. CANVAS GENERATION ENGINE
        fig, ax = plt.subplots(figsize=(12, 9), dpi=120, subplot_kw={'projection': ccrs.PlateCarree()})
        ax.set_extent([100, 180, 0, 60])
        ax.add_feature(cfeature.LAND, facecolor='#f5f5f5', edgecolor='#d6d6d6')
        ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#333333')
        ax.add_feature(cfeature.BORDERS, linestyle='-', linewidth=0.4, edgecolor='#a0a0a0')
        
        gl = ax.gridlines(draw_labels=True, linestyle=':', alpha=0.4, color='#7f8c8d')
        gl.top_labels, gl.right_labels = False, False

        # Group and chronologically link coordinate pairs by forecast hour
        for _, group in df.groupby('sample'):
            sorted_group = group.sort_values('fxx')
            ax.plot(
                sorted_group['lon'], sorted_group['lat'], 
                color=cfg["line_color"], linestyle=cfg["line_style"], 
                linewidth=0.8, alpha=0.5, transform=ccrs.PlateCarree()
            )
            
        ax.scatter(df['lon'], df['lat'], edgecolors=cmap(norm(df['pressure'])), facecolors='none', s=25, linewidths=1.2, transform=ccrs.PlateCarree())
        
        # Labels & Final File Compilations
        plt.colorbar(plt.cm.ScalarMappable(cmap=cmap, norm=norm), ax=ax, pad=0.03, fraction=0.04, aspect=30).set_label('Minimum Sea Level Pressure (hPa)', weight='bold')
        plt.title(cfg["title"], fontsize=15, fontweight='bold', pad=20)
        plt.text(0.5, 1.01, f"Initial Run: {yyyy}-{mm}-{dd} {cycle_str} | DeepMind WeatherLab Pipeline", transform=ax.transAxes, ha='center', fontsize=11, color='#555555')
        
        plt.savefig(output_png, bbox_inches='tight')
        plt.close(fig)
        print(f"--> Asset updated completely: {output_png}")
        
    except Exception as e:
        print(f"--> Engine process broke during execution for {model_name}: {e}")
        continue
EOF

    # 4. REMOTE PRODUCTION REPO SYNCHRONIZATION
    echo "Pushing Weather Lab layers to repository remote host..."
    git add .
    git commit -m "Automated Sync: GENC & FNV3 cyclogenesis structures updated for $(date +%Y%m%d_%H%MZ)"
    git push origin main
    
    echo "========================================================="
    echo "Cycle execution complete. Sleeping for 6 hours..."
    echo "========================================================="
    sleep 21600
done