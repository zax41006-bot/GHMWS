#!/bin/bash

WORKSPACE="/Users/eknlau/VS_code/GHMWS/ensemble-track"
cd "$WORKSPACE"

echo "========================================================="
echo " Starting Google Weather Lab Path-Optimized Engine"
echo "========================================================="

while true; do
    echo "--- Cycle Sync Attempt Started at $(date) ---"

    python3.11 << 'EOF'
import os
import requests
import pandas as pd
from datetime import datetime, timedelta

# --- MATPLOTLIB HEADLESS RUNTIME ---
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature

base_path = "/Users/eknlau/VS_code/GHMWS/ensemble-track/wp"

models = {
    "GENC": {
        "title": "GENC Ensemble Tracks - GHMWS"
    },
    "FNV3": {
        "title": "FNV3 Ensemble Tracks - GHMWS"
    }
}

bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
cmap = mcolors.ListedColormap(['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080'])
norm = mcolors.BoundaryNorm(bounds, cmap.N)

for model_name, cfg in models.items():
    print(f"[{datetime.now()}] Initializing search engine for {model_name}...")
    
    success = False
    for lookback_hours in range(0, 25, 6):
        now_utc = datetime.utcnow() - timedelta(hours=lookback_hours)
        
        if now_utc.hour >= 19:
            init_date_dt = now_utc
            init_time = 12
        elif now_utc.hour >= 13:
            init_date_dt = now_utc
            init_time = 6
        elif now_utc.hour >= 7:
            init_date_dt = now_utc
            init_time = 0
        elif now_utc.hour >= 1:
            init_date_dt = now_utc - timedelta(days=1)
            init_time = 18
        else:
            init_date_dt = now_utc - timedelta(days=1)
            init_time = 12
        
        yyyy = now_utc.strftime("%Y")
        mm = now_utc.strftime("%m")
        dd = now_utc.strftime("%d")
        date_folder = f"{yyyy}{mm}{dd}"
        cycle_str = f"{init_time:02d}Z"
        time_stamp_str = f"{yyyy}_{mm}_{dd}T{init_time:02d}_00"
        
        target_url = f"https://deepmind.google.com/science/weatherlab/download/cyclones/{model_name}/ensemble/cyclogenesis/csv/{model_name}_{time_stamp_str}_cyclogenesis.csv"
        
        print(f"--> Checking availability for {cycle_str} ({yyyy}-{mm}-{dd})...")
        
        try:
            r = requests.get(target_url, timeout=10)
            if r.status_code != 200:
                continue
                
            if r.text.lstrip().startswith("<!DOCTYPE html>") or "<html" in r.text.lower():
                continue
                
            path_2 = f"/Users/eknlau/VS_code/GHMWS/ensemble-track/wp/{model_name}/"
            run_dir = os.path.join(path_2, date_folder, cycle_str)
            os.makedirs(run_dir, exist_ok=True)
            
            local_csv_path = os.path.join(run_dir, f"{model_name.lower()}-unpaired-NWP.csv")
            archive_png = os.path.join(run_dir, "240.png")            
            latest_png = os.path.join(path_2, "240.png")
            
            with open(local_csv_path, 'wb') as f:
                f.write(r.content)
                
            # FIX 1: Add comment='#' to bypass Google's legal notice header lines
            df_2 = pd.read_csv(local_csv_path, comment='#')
            if df_2.empty:
                continue
                
            # FIX 2: Explicit map matching to your true file header keys
            if 'minimum_sea_level_pressure_hpa' in df_2.columns:
                df_2 = df_2.rename(columns={'minimum_sea_level_pressure_hpa': 'pressure'})
            
            # --- ADJUST NEGATIVE LONGITUDE HERE ---
            if 'lon' in df_2.columns:
                df_2.loc[df_2['lon'] < 0, 'lon'] += 360
            
            # Use 'valid_time' for perfect chronological track line connection sorting
            df_2 = df_2.sort_values(by=['track_id', 'sample', 'valid_time'])
            
            base_time_str = f"{yyyy}-{mm}-{dd} {cycle_str}"

            # -------------------------------------------------------------
            # INTEGRATED VISUALIZATION CANVAS
            # -------------------------------------------------------------
            fig = plt.figure(figsize=(12, 9), dpi=100)
            ax_2 = plt.axes(projection=ccrs.PlateCarree())
            ax_2.set_extent([100, 180, 0, 60], crs=ccrs.PlateCarree())

            ax_2.add_feature(cfeature.COASTLINE, linewidth=0.6, zorder=2)
            ax_2.add_feature(cfeature.BORDERS, linestyle=':', linewidth=0.4, zorder=2)
            ax_2.add_feature(cfeature.LAND, facecolor='#f5f5f5', zorder=1)

            gl = ax_2.gridlines(draw_labels=True, linestyle='--', alpha=0.5)
            gl.top_labels = False
            gl.right_labels = False

            # FIX 3: Group by track_id and sample matching the precise columns
            for _, group in df_2.groupby(['track_id', 'sample']):
                ax_2.plot(
                    group['lon'], group['lat'], color='gray', linewidth=0.6, alpha=0.2, 
                    transform=ccrs.PlateCarree(), zorder=3
                )

            sc = ax_2.scatter(
                df_2['lon'], df_2['lat'], 
                edgecolors=cmap(norm(df_2['pressure'])), 
                facecolors='none', 
                s=15,             
                linewidths=1.2,    
                alpha=0.9, 
                transform=ccrs.PlateCarree(), zorder=4
            )

            sm = plt.cm.ScalarMappable(cmap=cmap, norm=norm)
            cbar = plt.colorbar(sm, ax=ax_2, pad=0.04, fraction=0.05, aspect=25)
            cbar.set_label('Minimum Sea Level Pressure (hPa)', rotation=270, labelpad=20)
            cbar.set_ticks(bounds) 

            plt.title(cfg["title"], fontsize=16, fontweight='bold', pad=40, color='#1a237e')
            plt.text(0.5, 1.05, "360-hour Forecast", transform=ax_2.transAxes, ha='center', fontsize=13, fontweight='bold', color='#333333')
            plt.text(0.5, 1.02, f"Initial Time: {base_time_str}", transform=ax_2.transAxes, ha='center', fontsize=11, color='#546e7a')
            
            plt.savefig(archive_png, bbox_inches='tight') 
            plt.savefig(latest_png, bbox_inches='tight')  
            plt.close(fig)
            
            print(f"--> [SUCCESS] Processed {cycle_str}! Visual maps written safely.")
            success = True
            break 
            
        except Exception as e:
            print(f"    Internal cycle error for {cycle_str}: {e}")
            continue
            
    if not success:
        print(f"[WARN] Failed to find any valid recent cycles for {model_name} in the last 24 hours.")
EOF

    echo "Pushing updates to production repository main branch..."
    git add .
    git commit -m "Automated Sync: Core track headers aligned to true WeatherLab output specs"
    git push origin main
    
    echo "========================================================="
    
    # =========================================================
    # DYNAMIC SLEEP CALCULATION (Snaps to 02, 08, 14, 20 UTC)
    # =========================================================
    CURRENT_HOUR=$(date -u +%-H)
    CURRENT_MIN=$(date -u +%-M)
    CURRENT_SEC=$(date -u +%-S)

    # Determine the next sequential target interval
    if [ $CURRENT_HOUR -lt 2 ]; then NEXT_TARGET=2
    elif [ $CURRENT_HOUR -lt 8 ]; then NEXT_TARGET=8
    elif [ $CURRENT_HOUR -lt 14 ]; then NEXT_TARGET=14
    elif [ $CURRENT_HOUR -lt 20 ]; then NEXT_TARGET=20
    else NEXT_TARGET=26 # 26 represents 02:00Z the next calendar day
    fi

    HOURS_TO_WAIT=$((NEXT_TARGET - CURRENT_HOUR - 1))
    MINS_TO_WAIT=$((59 - CURRENT_MIN))
    SECS_TO_WAIT=$((60 - CURRENT_SEC))

    TOTAL_SLEEP=$(( (HOURS_TO_WAIT * 3600) + (MINS_TO_WAIT * 60) + SECS_TO_WAIT ))

    echo "Cycle execution complete. Snapping to next target interval ($((NEXT_TARGET % 24)):00Z)."
    echo "Sleeping for $TOTAL_SLEEP seconds..."
    echo "========================================================="
    
    sleep $TOTAL_SLEEP
done