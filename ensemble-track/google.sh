#!/bin/bash

# Define core configuration variables
WORKSPACE="/Users/eknlau/VS_code/GHMWS/ensemble-track"
cd "$WORKSPACE"

echo "========================================================="
echo " Starting Google Weather Lab Tracker Pipeline (FNV3/GENC)"
echo "========================================================="

while true; do
    echo "--- Operational Cycle Started at $(date) ---"

    # Execute Python engine directly via Here-Doc execution
    python3.11 << 'EOF'
import os
import pandas as pd
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature

base_path = "/Users/eknlau/VS_code/GHMWS/ensemble-track/wp"

# 1. COMPUTE CURRENT CYCLICAL TIMING WINDOW
now_utc = datetime.utcnow()
if now_utc.hour >= 21: init_date_dt, init_time = now_utc, 12
elif now_utc.hour >= 15: init_date_dt, init_time = now_utc, 6
elif now_utc.hour >= 9: init_date_dt, init_time = now_utc, 0
elif now_utc.hour >= 3: init_date_dt, init_time = now_utc - timedelta(days=1), 18
else: init_date_dt, init_time = now_utc - timedelta(days=1), 12

date_folder = init_date_dt.strftime("%Y%m%d")
cycle_str = f"{init_time:02d}Z"

# Meta configuration mapping for the target Weather Lab baselines
models = {
    "FNV3": {
        "file_suffix": "fnv3-unpaired-NWP.csv",
        "line_color": "#ff5722",
        "line_style": "-",
        "title": "Google Weather Lab FNV3 Ensemble Tracks"
    },
    "GENC": {
        "file_suffix": "genc-unpaired-NWP.csv",
        "line_color": "#009688",
        "line_style": "--",
        "title": "Google Weather Lab GENC Unpaired Ensemble"
    }
}

# 2. CYCLICAL MATPLOTLIB FORMATTING SETUP
bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
cmap = mcolors.ListedColormap(['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080'])
norm = mcolors.BoundaryNorm(bounds, cmap.N)

for model_name, cfg in models.items():
    model_dir = os.path.join(base_path, model_name, date_folder, cycle_str)
    csv_path = os.path.join(model_dir, cfg["file_suffix"])
    output_png = os.path.join(model_dir, "240.png")
    
    if not os.path.exists(csv_path):
        print(f"[{datetime.now()}] [WARN] Path target not found for {model_name}: {csv_path}")
        continue
        
    print(f"[{datetime.now()}] Processing data for {model_name}...")
    df = pd.read_csv(csv_path)
    
    if df.empty:
        print(f"Empty data frames detected for {model_name}. Skipping visualization.")
        continue

    # Initialize geospatial map canvas
    fig, ax = plt.subplots(figsize=(12, 9), dpi=120, subplot_kw={'projection': ccrs.PlateCarree()})
    ax.set_extent([100, 180, 0, 60])
    ax.add_feature(cfeature.LAND, facecolor='#f5f5f5', edgecolor='#d6d6d6')
    ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#333333')
    ax.add_feature(cfeature.BORDERS, linestyle='-', linewidth=0.4, edgecolor='#a0a0a0')
    
    gl = ax.gridlines(draw_labels=True, linestyle=':', alpha=0.4, color='#7f8c8d')
    gl.top_labels, gl.right_labels = False, False

    # 3. CHRONOLOGICAL PLOTTING FIX
    # Group by ensemble member, then explicitly sort values chronologically by forecast step
    for _, group in df.groupby('sample'):
        sorted_group = group.sort_values('fxx')
        ax.plot(
            sorted_group['lon'], 
            sorted_group['lat'], 
            color=cfg["line_color"], 
            linestyle=cfg["line_style"], 
            linewidth=0.8, 
            alpha=0.5,
            transform=ccrs.PlateCarree()
        )
        
    # Overlay normalized central intensity scatter points
    sc = ax.scatter(
        df['lon'], 
        df['lat'], 
        edgecolors=cmap(norm(df['pressure'])), 
        facecolors='none', 
        s=25, 
        linewidths=1.2,
        transform=ccrs.PlateCarree()
    )
    
    # Metadata text tags
    plt.colorbar(plt.cm.ScalarMappable(cmap=cmap, norm=norm), ax=ax, pad=0.03, fraction=0.04, aspect=30).set_label('Minimum Sea Level Pressure (hPa)', weight='bold')
    plt.title(cfg["title"], fontsize=15, fontweight='bold', pad=20)
    plt.text(0.5, 1.01, f"Initial Run Window: {init_date_dt.strftime('%Y-%m-%d')} {cycle_str} | 240h Horizon", transform=ax.transAxes, ha='center', fontsize=11, color='#555555')
    
    # Save clear asset back to standard output directory matrix
    plt.savefig(output_png, bbox_inches='tight')
    plt.close(fig)
    print(f"[{datetime.now()}] Plot generation complete: {output_png}")
EOF

    # 4. REMOTE GIT RESYNCHRONIZATION 
    echo "Staging updated tracking matrices to remote repository..."
    git add .
    git commit -m "Automated update: Google Weather Lab (FNV3/GENC) tracks for $(date +%Y%m%d_%H%MZ)"
    git push origin main
    
    echo "========================================================="
    echo "Cycle execution complete. Sleeping for 6 hours..."
    echo "========================================================="
    sleep 21600
done