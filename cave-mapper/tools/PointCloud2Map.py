# This script will parse the point clouds created by CaveDiveMapApp.
# It will generate a map based on the data of the pointcloud


import numpy as np
import matplotlib.pyplot as plt
from shapely.geometry import MultiPoint, LineString, MultiLineString
from shapely.ops import polygonize, unary_union
from scipy.spatial import Delaunay
from plyfile import PlyData
import re

def read_ply(filepath):
    plydata = PlyData.read(filepath)
    vertex = plydata['vertex']
    points = np.vstack((vertex['x'], vertex['y'], vertex['z'])).T
    colors = np.vstack((vertex['red'], vertex['green'], vertex['blue'])).T / 255.0
    return points, colors

def segment_pointcloud(points, colors):
    yellow_mask = (colors[:, 0] > 0.8) & (colors[:, 1] > 0.8) & (colors[:, 2] < 0.3)
    centerline_pts = points[yellow_mask]
    wall_pts = points[~yellow_mask]
    return centerline_pts, wall_pts



def alpha_shape(points, alpha=0.05):
    """Compute the alpha shape (concave hull) of a set of 2D points."""
    if len(points) < 4:
        return MultiPoint(points).convex_hull

    tri = Delaunay(points)
    triangles = points[tri.simplices]

    a = np.linalg.norm(triangles[:, 0] - triangles[:, 1], axis=1)
    b = np.linalg.norm(triangles[:, 1] - triangles[:, 2], axis=1)
    c = np.linalg.norm(triangles[:, 2] - triangles[:, 0], axis=1)

    s = (a + b + c) / 2.0
    area = np.sqrt(np.maximum(0, s * (s - a) * (s - b) * (s - c)))  # numerical safety

    with np.errstate(divide='ignore', invalid='ignore'):
        circum_r = (a * b * c) / (4.0 * area)
        circum_r[np.isnan(circum_r)] = np.inf  # invalid triangles

    threshold = 1.0 / alpha
    valid = circum_r < threshold
    triangles = tri.simplices[valid]

    edges = set()
    for tri in triangles:
        for i in range(3):
            edge = tuple(sorted((tri[i], tri[(i + 1) % 3])))
            if edge in edges:
                edges.remove(edge)
            else:
                edges.add(edge)

    edge_lines = [LineString([points[i], points[j]]) for i, j in edges]
    m = MultiLineString(edge_lines)
    polygons = list(polygonize(m))

    if not polygons:
        return MultiPoint(points).convex_hull  # fallback
    return unary_union(polygons)



def plot_projection(wall_pts, centerline_pts, view='top', alpha=0.01, ax=None):
    if view == 'top':
        proj_wall = wall_pts[:, [0, 2]]  # X-Z
        proj_center = centerline_pts[:, [0, 2]]
        xlabel, ylabel, title = "X", "Z", "Top View (X-Z)"
    else:
        proj_wall = wall_pts[:, [0, 1]]  # X-Y
        proj_center = centerline_pts[:, [0, 1]]
        xlabel, ylabel, title = "X", "Y", "Side View (X-Y)"

    shape = alpha_shape(proj_wall, alpha=alpha)

    ax.scatter(proj_wall[:, 0], proj_wall[:, 1], s=0.5, color='gray', label='Walls')
    ax.plot(proj_center[:, 0], proj_center[:, 1], color='yellow', label='Centerline')
    if shape.geom_type == 'Polygon':
        x, y = shape.exterior.xy
        ax.plot(x, y, color='blue', linewidth=1, label='Wall Contour')

    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.axis('equal')
    ax.legend()
    
    
    

def main():
    filepath = "point.ply"  # Update with your file path

    # Ask for cave name
    cave_name = input("Enter cave name (for title and filename): ").strip()
    if not cave_name:
        cave_name = "Unnamed Cave"

    # Create a filesystem-safe filename fragment from the cave name
    safe_name = re.sub(r'[^A-Za-z0-9._-]+', '_', cave_name).strip('_')
    if not safe_name:
        safe_name = "unnamed_cave"

    points, colors = read_ply(filepath)
    centerline_pts, wall_pts = segment_pointcloud(points, colors)

    # Compute total distance along centerline
    if len(centerline_pts) > 1:
        segment_lengths = np.linalg.norm(np.diff(centerline_pts, axis=0), axis=1)
        total_distance = np.sum(segment_lengths)
    else:
        total_distance = 0.0
        
    # Compute max depth (lowest Z value among wall points)
    max_depth = np.min(wall_pts[:, 2])
    print(f"Max Depth: {max_depth:.2f} meters")


    # Compute compass orientation (based on X-Z projection)
    vec = centerline_pts[-1] - centerline_pts[0]
    angle_rad = np.arctan2(vec[0], vec[2])  # X-Z plane
    angle_deg = np.degrees(angle_rad)
    direction = (angle_deg + 360) % 360  # Normalize to [0, 360)

    # Create figure
    fig, axes = plt.subplots(1, 2, figsize=(16, 7))
    plot_projection(wall_pts, centerline_pts, view='top', alpha=0.2, ax=axes[0])
    plot_projection(wall_pts, centerline_pts, view='side', alpha=0.2, ax=axes[1])

    # Annotate total distance and include cave name
    fig.suptitle(f"{cave_name} | Total Length: {total_distance:.2f} m | Max Depth: {-max_depth:.2f} m",
     fontsize=14, fontweight='bold')

    # Add compass rose as an inset in the top view
    from matplotlib.patches import FancyArrow
    inset_ax = fig.add_axes([0.15, 0.75, 0.1, 0.1])  # [left, bottom, width, height]
    inset_ax.set_xlim(-1.5, 1.5)
    inset_ax.set_ylim(-1.5, 1.5)
    inset_ax.axis('off')
    inset_ax.set_aspect('equal')

    # Draw North arrow
    dx = np.sin(angle_rad)
    dy = np.cos(angle_rad)
    inset_ax.add_patch(FancyArrow(0, 0, dx, dy,
                                  width=0.05, head_width=0.2, head_length=0.3,
                                  color='red'))
    inset_ax.text(0, 1.2, "N", color='red', ha='center', va='center', fontsize=10, fontweight='bold')
    inset_ax.text(0, -1.2, f"{int(direction)}°", color='black', ha='center', va='center', fontsize=8)
    inset_ax.set_title("Compass", fontsize=9)

    plt.tight_layout(rect=[0, 0, 1, 0.95])
    
    # Save the figure as a PDF; include cave name in filename
    output_filename = f"cave_map_{safe_name}.pdf"
    fig.savefig(output_filename, format="pdf")
    print(f"Saved map to {output_filename}")

    plt.show()


if __name__ == "__main__":
    main()
