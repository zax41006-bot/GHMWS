#!/bin/bash
BRANCH="main"
SAVE_DIR="/Users/eknlau/Desktop/CWA/accu_rain"
SAVE_DIR_2="/Users/eknlau/VS_code/GHMWS/model/CWA/accu_rain"
mkdir -p "$SAVE_DIR"
mkdir -p "$SAVE_DIR_2"

while true; do
    echo "--- 任務開始: $(date) ---"
    git pull origin "$BRANCH" --rebase

    URL="https://cwaopendata.s3.ap-northeast-1.amazonaws.com/Model"
    PREFIX="M-A0064"

    # Use one loop: j is the number, i is the 0-padded string (000, 006...)
    for j in $(seq 0 6 84); do
        i=$(printf "%03d" $j)
        
        SOURCE_FILE="${PREFIX}-${i}.grb2"
        FILE_PATH="${SAVE_DIR}/${i}.grb2"
        IMAGE_PATH=${SAVE_DIR_2}/${j}.png
    
        echo "Downloading ${SOURCE_FILE}..."
        curl -L "${URL}/${SOURCE_FILE}" -o "${FILE_PATH}"

        # No single quotes around EOF_PYTHON so $i and $j variables work
        python3.11 << EOF_PYTHON
import xarray as xr
import numpy as np
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import cfgrib
import pandas as pd
from herbie import Herbie
from herbie.toolbox import EasyMap, pc
from herbie import paint


try:
    # Use the Shell variables directly in the Python code
    datasets = cfgrib.open_datasets("${FILE_PATH}")
    
    # Using index 4 for precipitation as per your original script
    data = datasets[4]
    
    fig = plt.figure(figsize=(12, 12))
    ax = plt.axes(projection=ccrs.PlateCarree())

    # Map Features
    ax.add_feature(cfeature.STATES.with_scale('10m'), linewidths=0.5, edgecolor='k')
    ax.add_feature(cfeature.BORDERS.with_scale('10m'), linewidths=1.0, edgecolor='k')
    ax.add_feature(cfeature.COASTLINE.with_scale('10m'), linewidths=1.0, edgecolor='k')
    ax.add_feature(cfeature.LAND.with_scale('10m'), facecolor='#EEEEEE')

    # Plot Data - Kept your original cmap and levels
    p = ax.contourf(
        data.longitude, data.latitude, data.unknown,
        transform=ccrs.PlateCarree(),
        cmap='radar.reflectivity',
        extend='max',
        levels=[0.1,1,2,5,10,20,30,40,50,70,100,150,200,250,300,400,500,600]
    )

    cb = plt.colorbar(p, ax=ax, orientation="horizontal", pad=0.05)
    cb.set_label('mm', size='x-large')
    
    gl = ax.gridlines(draw_labels=True)
    gl.top_labels = False
    gl.right_labels = False

    ax.set_extent([105, 125, 15, 30]) 
    
    # valid_time and time values
    v_time = data.unknown.valid_time.values
    i_time = data.unknown.time.values

    valid_UTC = pd.to_datetime(v_time).strftime('%H:%M UTC %d %b %Y')
    valid_CST = (pd.to_datetime(v_time) + pd.Timedelta(hours=8)).strftime('%H:%M CST %d %b %Y')
    init_UTC = pd.to_datetime(i_time).strftime('%H:%M UTC %d %b %Y')
    init_CST = (pd.to_datetime(i_time) + pd.Timedelta(hours=8)).strftime('%H:%M CST %d %b %Y')

    ax.set_title(f"CWA WRF: 3km resolution\nValid: {valid_UTC} or {valid_CST}\ninitialized at {init_UTC} or {init_CST}\nForecast Hour: ${j}\n", loc="left")
    ax.set_title("Accumulated Precipitation", loc="right")
    
    plt.savefig("${IMAGE_PATH}", dpi=150)
    plt.close()
    print("✅ Saved ${j}.png")

except Exception as e:
    print(f"❌ Failed to plot ${j}: {e}")
EOF_PYTHON
    done

    ./cwa_wrf_surf.sh
    ./cwa_wrf_small.sh
    
    git add .
    if ! git diff-index --quiet HEAD; then
        git commit -m "Auto-update: CWA WRF \$(date +'%Y-%m-%d %H:%M')"
        git push origin "$BRANCH"
        echo "✅ GitHub 同步成功"
    else
        echo "😴 無變動"
    fi

    echo "等待 6 小時..."
    sleep 21600
done
