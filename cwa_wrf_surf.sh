URL="https://cwaopendata.s3.ap-northeast-1.amazonaws.com/Model"
PREFIX="M-A0064"
SAVE_DIR="/Users/eknlau/VS_code/GHMWS/model/CWA/2m_temp_10m_wind"
ORIGIN="/Users/eknlau/Desktop/CWA/accu_rain"
for j in $(seq 0 6 84); do
    i=$(printf "%03d" $j)
    SOURCE_FILE="${PREFIX}-${i}.grb2"
    LOCAL_NAME="${i}.grb2"
    FILE_PATH="${SAVE_DIR}/${LOCAL_NAME}"
    IMAGE_PATH="${SAVE_DIR}/${j}.png"

    # Run Python Plotting
    python3.11 << EOF
import xarray as xr
import numpy as np
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import cfgrib
import pandas as pd

try:
    # Open dataset
    data=cfgrib.open_datasets("${ORIGIN}/${LOCAL_NAME}")
    fig = plt.figure(figsize=(10,10))
    ax = plt.axes(projection=ccrs.PlateCarree())

    ax.add_feature(cfeature.STATES.with_scale('10m'), linewidths=0.5, linestyle='solid', edgecolor='k')
    ax.add_feature(cfeature.BORDERS.with_scale('10m'), linewidths=1.0, linestyle='solid', edgecolor='k')
    ax.add_feature(cfeature.COASTLINE.with_scale('10m'), linewidths=1.0, linestyle='solid', edgecolor='k')
    ax.add_feature(cfeature.LAND.with_scale('10m'),facecolor='#EEEEEE')
    p = ax.contourf(
        data[1].longitude,
        data[1].latitude,
        data[1].t2m-273.15,
        transform=ccrs.PlateCarree(),
        cmap="nipy_spectral",
        levels=np.arange(-5,40,1)
    )
    y=plt.colorbar(p, ax=ax, orientation="horizontal", pad=0.05, cmap='gist_ncar')
    y.set_label('degree Celsius',size='x-large')
    gl=ax.gridlines(draw_labels=True)
    gl.xlabels_top = False
    gl.ylabels_left = False
    skip = (slice(None, None, 20), slice(None, None, 20))
    ax.barbs(data[0].longitude[skip],data[0].latitude[skip],data[0].u10[skip]*3.6/1.852,data[0].v10[skip]*3.6/1.852,barbcolor='red',transform=ccrs.PlateCarree(),flip_barb=False,length=7)
    
    ax.set_extent([105,125,15,30])
    valid_UTC = data[1].t2m.valid_time.dt.strftime('%H:%M UTC %d %b %Y').item()
    valid_CST=(pd.to_datetime(data[1].t2m.valid_time.values+pd.Timedelta(hours=8))).strftime('%H:%M CST/HKT/MST %d %b %Y')
    init_UTC = data[1].t2m.time.dt.strftime('%H:%M UTC %d %b %Y').item()
    init_CST = (pd.to_datetime(data[1].t2m.time.values) + pd.Timedelta(hours=8)).strftime('%H:%M CST/HKT/MST %d %b %Y')
    ax.set_title(f"CWA WRF: 3km resolution\nValid: {valid_UTC} or {valid_CST}\ninitialized at {init_UTC} or {init_CST}\nForecast Hour: ${i}\n", loc="left")
    ax.set_title("2m temperature and 10m wind", loc="right")
    plt.savefig("$IMAGE_PATH", dpi=150)
    plt.close()
    print("✅ Saved ${j}.png")

except Exception as e:
    print(f"❌ Failed to plot ${j}: {e}")
EOF
done

echo "All tasks finished."
