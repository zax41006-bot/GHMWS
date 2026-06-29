import os
import sys
import time
from datetime import datetime, timedelta
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from ecmwf.opendata import Client
import earthkit.data

def generate_aifs_ensemble_plot():
    # 1. Dynamically compute the closest operational AIFS model run (00Z or 12Z)
    now_utc = datetime.utcnow()
    
    if now_utc.hour >= 18:
        init_date_dt = now_utc
        init_time = 12
    elif now_utc.hour >= 6:
        init_date_dt = now_utc
        init_time = 0
    else:
        # Before 06 UTC, fallback to yesterday's 12Z run
        init_date_dt = now_utc - timedelta(days=1)
        init_time = 12

    init_date = init_date_dt.strftime("%Y-%m-%d")
    date_folder_str = init_date_dt.strftime("%Y%m%d") # E.g., 20260629
    time_str = f"{init_time:02d}Z"                    # E.g., 00Z or 12Z

    # 2. Re-route paths to match your 3-tier cascade folder strategy (AIFS directory)
    # Directory structure outcome: .../ensemble-track/wp/AIFS/20260629/00Z/
    path = f"/Users/eknlau/VS_code/GHMWS/ensemble-track/wp/AIFS/{date_folder_str}/{time_str}/"
    if not os.path.exists(path):
        os.makedirs(path)

    # Asset naming schema matching the frontend engine's request format
    target_bufr = os.path.join(path, f"aifs-{init_date}-{time_str}.bufr")
    csv_nwp = os.path.join(path, f"aifs-{init_date}-{time_str}-NWP.csv")
    output_png = os.path.join(path, "240.png")

    print(f"[{datetime.now()}] Attempting download for AIFS {init_date} {time_str}...")

    try:
        # Request data from ecmwf client targeting aifs-ens model group
        client = Client(source="ecmwf", model="aifs-ens")
        client.retrieve(
            date=init_date, 
            time=init_time, 
            type="tf", 
            stream="enfo", 
            step=360, 
            target=target_bufr
        )
    except Exception as e:
        print(f"AIFS download failed or data is not published yet: {e}. Retrying on next loop cycle.")
        return

    # 3. Parse BUFR data pipeline
    ds = earthkit.data.from_source("file", target_bufr)
    df = ds.to_pandas(
        columns=["stormIdentifier", "ensembleMemberNumber", "typicalDate", "typicalTime", 
                 "year", "month", "day", "hour", "latitude", "longitude", "pressureReducedToMeanSeaLevel"],
        filters={"meteorologicalAttributeSignificance": 1},
        required_columns=True
    )

    df = df.dropna(subset=['year', 'month', 'day', 'hour', 'longitude', 'latitude']).copy()

    # Calculate steps and pressure mapping variables
    b_date = df['typicalDate'].astype(int).astype(str)
    b_time = df['typicalTime'].astype(int).astype(str).str.zfill(4) 
    df['base_dt'] = pd.to_datetime((b_date + b_time).str[:12], format='%Y%m%d%H%M')

    df['valid_dt'] = pd.to_datetime(df[['year', 'month', 'day', 'hour']])
    df['hours'] = (df['valid_dt'] - df['base_dt']).dt.total_seconds() / 3600
    df['pressure'] = df['pressureReducedToMeanSeaLevel'] / 100.0

    df = df.rename(columns={"stormIdentifier": "track", "ensembleMemberNumber": "sample", 
                            "longitude": "lon", "latitude": "lat"})

    # Filter out Northwest Pacific Typhoons (Suffix 'W')
    df_nwp = df[df['track'].astype(str).str.endswith('W', na=False)].copy()
    df_nwp.to_csv(csv_nwp, index=False, encoding='utf-8-sig')

    if df_nwp.empty:
        print(f"Warning: No AIFS track data found for the selected time {init_date} {time_str}")
        return

    base_time_str = df_nwp['base_dt'].iloc[0].strftime('%Y-%m-%d %H:%MZ')

    # 4. Color map configuration configurations
    bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
    colors = ['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080']
    cmap = mcolors.ListedColormap(colors)
    norm = mcolors.BoundaryNorm(bounds, cmap.N)

    # 5. Georeferenced Mapping Canvas Layout Generation (Cartopy)
    fig = plt.figure(figsize=(12, 9), dpi=120, facecolor='#ffffff')
    ax = plt.axes(projection=ccrs.PlateCarree())
    ax.set_extent([100, 180, 0, 60], crs=ccrs.PlateCarree())

    ax.add_feature(cfeature.OCEAN, facecolor='#f9fbfc', zorder=0)
    ax.add_feature(cfeature.LAND, facecolor='#f0f2f0', edgecolor='#bcbcbc', linewidth=0.5, zorder=1)
    ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#454545', zorder=2)
    ax.add_feature(cfeature.BORDERS, linestyle='-', linewidth=0.4, edgecolor='#95a5a6', zorder=2)

    gl = ax.gridlines(draw_labels=True, linestyle=':', alpha=0.4, color='#7f8c8d', zorder=3)
    gl.top_labels = False
    gl.right_labels = False

    # Draw tracks lines with distinctive deep blue dashed notation matching your config
    for _, group in df_nwp.groupby(['track', 'sample']):
        ax.plot(group['lon'], group['lat'], color='#1e88e5', linestyle='--', linewidth=0.5, alpha=0.3, 
                transform=ccrs.PlateCarree(), zorder=4)

    # Scatter plotted points tracking system center points
    sc = ax.scatter(df_nwp['lon'], df_nwp['lat'], 
                    edgecolors=cmap(norm(df_nwp['pressure'])), 
                    facecolors='none', 
                    s=20, 
                    linewidths=1.2, 
                    alpha=0.9, 
                    transform=ccrs.PlateCarree(), zorder=5)

    sm = plt.cm.ScalarMappable(cmap=cmap, norm=norm)
    cbar = plt.colorbar(sm, ax=ax, pad=0.03, fraction=0.04, aspect=30)
    cbar.set_label('Minimum Sea Level Pressure (hPa)', fontsize=10, labelpad=10, fontweight='bold')
    cbar.ax.tick_params(labelsize=9)

    # Titles and Subtitles Metadata Strings
    plt.title("AIFS Ensemble Tracks - GHMWS", fontsize=16, fontweight='bold', pad=40, color='#0d47a1')
    plt.text(0.5, 1.05, "360-hour Forecast (aifs-ens)", transform=ax.transAxes, ha='center', fontsize=13, fontweight='bold', color='#333333')
    plt.text(0.5, 1.02, f"Initial Time: {base_time_str}", transform=ax.transAxes, ha='center', fontsize=11, color='#546e7a')

    # Save figure reference cleanly without pausing script thread loops
    plt.savefig(output_png, bbox_inches='tight')
    plt.close(fig)
    print(f"[{datetime.now()}] Success: Saved AIFS plot asset to -> {output_png}")

# ==================== AUTOMATED WATCHER CYCLE =======================
if __name__ == "__main__":
    print("Starting automated AIFS ensemble track generation script service loop...")
    while True:
        generate_aifs_ensemble_plot()
        
        # Sleep for 12 hours (43200 seconds) before checking for the next model cycle update
        print("Sleeping for 43200 seconds...")
        time.sleep(43200)