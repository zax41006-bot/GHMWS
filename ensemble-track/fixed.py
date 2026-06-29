import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.crs as ccrs
import cartopy.feature as cfeature

# Change these to match the exact folder you want to fix!
base_path = "/Users/eknlau/VS_code/GHMWS/ensemble-track/wp/"
date_folder = "20260628"  # YYYYMMDD
cycle_folder = "18Z"      # HHZ

models = {
    "GEFS": ('#43a047', '-', "240-hour Forecast"),
    "AIGEFS": ('#e040fb', '--', "240-hour Forecast (AI)")
}

bounds = [900, 915, 930, 945, 960, 970, 980, 990, 1000, 1010]
cmap = mcolors.ListedColormap(['#4a148c', '#880e4f', '#b71c1c', '#e65100', '#ff8f00', '#fbc02d', '#4db6ac', '#0277bd', '#808080'])
norm = mcolors.BoundaryNorm(bounds, cmap.N)

for model_type, (line_color, line_style, subtitle) in models.items():
    csv_path = os.path.join(base_path, model_type, date_folder, cycle_folder, f"{model_type.lower()}-NWP.csv")
    output_png = os.path.join(base_path, model_type, date_folder, cycle_folder, "240.png")
    
    if not os.path.exists(csv_path):
        print(f"Skipping {model_type}, CSV not found at: {csv_path}")
        continue
        
    print(f"Fixing {model_type} plot using historical CSV data...")
    df_nwp = pd.read_csv(csv_path)
    
    # Recreate the Map Canvas
    fig, ax = plt.subplots(figsize=(12, 9), dpi=120, subplot_kw={'projection': ccrs.PlateCarree()})
    ax.set_extent([100, 180, 0, 60])
    ax.add_feature(cfeature.LAND, facecolor='#f0f2f0', edgecolor='#bcbcbc')
    ax.add_feature(cfeature.COASTLINE, linewidth=0.7, edgecolor='#454545')
    
    # THE CRITICAL FIX: Group by member, then explicitly sort by forecast hour (fxx)
    for _, group in df_nwp.groupby('sample'):
        sorted_group = group.sort_values('fxx')
        ax.plot(
            sorted_group['lon'], 
            sorted_group['lat'], 
            color=line_color, 
            linestyle=line_style, 
            linewidth=0.6, 
            alpha=0.4
        )
        
    # Overlay the intensity scatter points
    ax.scatter(df_nwp['lon'], df_nwp['lat'], edgecolors=cmap(norm(df_nwp['pressure'])), facecolors='none', s=20)
    
    # Formatting elements
    plt.colorbar(plt.cm.ScalarMappable(cmap=cmap, norm=norm), ax=ax, pad=0.03, fraction=0.04, aspect=30).set_label('MSLP (hPa)')
    plt.title(f"{model_type} Ensemble Tracks - GHMWS", fontsize=16, fontweight='bold')
    plt.text(0.5, 1.02, subtitle, transform=ax.transAxes, ha='center', fontsize=12)
    
    plt.savefig(output_png, bbox_inches='tight')
    plt.close(fig)
    print(f"Successfully replaced corrupted image for {model_type}!")