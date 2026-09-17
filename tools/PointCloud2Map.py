# Parses the point clouds produced by CaveDiveMap's VIO mode and renders a map.
#
# Coordinate conventions, as declared in the PLY header:
#   * The cloud is gravity-aligned: +Y is up. Depth is therefore measured on Y,
#     positive downwards, relative to the start of the centerline.
#   * The ARKit yaw origin is arbitrary. If the surveyor tapped SET N, the header
#     carries `comment north_offset_deg`, which converts an in-cloud azimuth to a
#     compass bearing:  bearing = atan2(x, -z) + north_offset.
#   * Yellow vertices are the centerline; everything else is wall.

import argparse
import math
from urllib.parse import unquote

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrow
from shapely.geometry import MultiPoint, LineString, MultiLineString
from shapely.ops import polygonize, unary_union
from scipy.spatial import Delaunay
from plyfile import PlyData


def read_ply(filepath):
    plydata = PlyData.read(filepath)
    vertex = plydata['vertex']
    points = np.vstack((vertex['x'], vertex['y'], vertex['z'])).T
    colors = np.vstack((vertex['red'], vertex['green'], vertex['blue'])).T / 255.0
    # `segment` marks tracking continuity and is absent from clouds written by
    # older builds; treat those as a single unbroken run.
    names = {p.name for p in vertex.properties}
    segments = np.asarray(vertex['segment']) if 'segment' in names \
        else np.zeros(len(points), dtype=int)
    return points, colors, segments, list(plydata.comments)


def split_runs(points, segments):
    """Splits the centerline wherever tracking was lost.

    Two stations either side of a gap were never connected by surveyed passage,
    so neither the drawn line nor the length total may cross the break.
    """
    runs, start = [], 0
    for i in range(1, len(points) + 1):
        if i == len(points) or segments[i] != segments[i - 1]:
            if i - start >= 1:
                runs.append((start, i))
            start = i
    return runs


def parse_header_metadata(comments):
    """Pulls the survey metadata CaveDiveMap writes into the PLY header."""
    meta = {'north_offset_deg': None, 'north_accuracy_deg': None,
            'north_reference': None, 'annotations': {}}
    for comment in comments:
        tokens = comment.split()
        if not tokens:
            continue
        key = tokens[0]
        if key == 'north_offset_deg' and len(tokens) > 1:
            meta['north_offset_deg'] = float(tokens[1])
        elif key == 'north_offset_accuracy_deg' and len(tokens) > 1:
            meta['north_accuracy_deg'] = float(tokens[1])
        elif key == 'north_reference' and len(tokens) > 1:
            meta['north_reference'] = tokens[1]
        elif key == 'annotation':
            vertex_index, text = None, None
            for i, token in enumerate(tokens):
                if token.startswith('vertex_index='):
                    vertex_index = int(token.split('=', 1)[1])
                elif token.startswith('text='):
                    raw = ' '.join(tokens[i:]).split('=', 1)[1]
                    # The app percent-encodes comment text so that non-ASCII notes
                    # survive a PLY header that must stay ASCII. Text written by
                    # older builds contains no escapes and decodes to itself.
                    text = unquote(raw)
                    break
            if vertex_index is not None and text:
                meta['annotations'][vertex_index] = text
    return meta


def segment_pointcloud(points, colors, segments):
    yellow_mask = (colors[:, 0] > 0.8) & (colors[:, 1] > 0.8) & (colors[:, 2] < 0.3)
    return points[yellow_mask], points[~yellow_mask], segments[yellow_mask]


def to_east_north(points, north_offset_deg):
    """Rotates the horizontal plane so +N is true north and +E is east.

    bearing = atan2(x, -z) + offset, and (E, N) = (r*sin(bearing), r*cos(bearing)).
    """
    theta = math.radians(north_offset_deg or 0.0)
    cos_t, sin_t = math.cos(theta), math.sin(theta)
    x, z = points[:, 0], points[:, 2]
    east = x * cos_t - z * sin_t
    north = -z * cos_t - x * sin_t
    return east, north


def alpha_shape(points, alpha=0.05):
    """Alpha shape (concave hull) of a set of 2D points."""
    if len(points) < 4:
        return MultiPoint(points).convex_hull

    triangulation = Delaunay(points)
    corners = points[triangulation.simplices]

    a = np.linalg.norm(corners[:, 0] - corners[:, 1], axis=1)
    b = np.linalg.norm(corners[:, 1] - corners[:, 2], axis=1)
    c = np.linalg.norm(corners[:, 2] - corners[:, 0], axis=1)

    s = (a + b + c) / 2.0
    area = np.sqrt(np.maximum(0, s * (s - a) * (s - b) * (s - c)))

    with np.errstate(divide='ignore', invalid='ignore'):
        circum_r = (a * b * c) / (4.0 * area)
        circum_r[np.isnan(circum_r)] = np.inf

    keep = triangulation.simplices[circum_r < (1.0 / alpha)]

    edges = set()
    for simplex in keep:
        for i in range(3):
            edge = tuple(sorted((simplex[i], simplex[(i + 1) % 3])))
            if edge in edges:
                edges.remove(edge)
            else:
                edges.add(edge)

    polygons = list(polygonize(MultiLineString(
        [LineString([points[i], points[j]]) for i, j in edges])))
    if not polygons:
        return MultiPoint(points).convex_hull
    return unary_union(polygons)


def plot_contour(ax, shape):
    """Draws the wall contour, handling both Polygon and MultiPolygon results.

    The previous version only handled Polygon, so any survey whose walls formed
    more than one blob silently lost its outline.
    """
    geoms = getattr(shape, 'geoms', None)
    parts = list(geoms) if geoms is not None else [shape]
    labelled = False
    for part in parts:
        if part.geom_type != 'Polygon':
            continue
        x, y = part.exterior.xy
        ax.plot(x, y, color='blue', linewidth=1,
                label=None if labelled else 'Wall Contour')
        labelled = True


def principal_axis(points_2d):
    """Dominant horizontal direction of the centerline, for the profile view."""
    if len(points_2d) < 2:
        return np.array([1.0, 0.0])
    centred = points_2d - points_2d.mean(axis=0)
    _, _, vt = np.linalg.svd(centred, full_matrices=False)
    return vt[0]


def main():
    parser = argparse.ArgumentParser(description="Render a cave map from a CaveDiveMap PLY.")
    parser.add_argument('filepath', nargs='?', default='point.ply')
    # Larger alpha hugs the walls more tightly. Too small and the hull bridges the
    # inside of a bend, drawing passage where there is none.
    parser.add_argument('--alpha', type=float, default=0.6, help='Alpha-shape tightness.')
    parser.add_argument('--out', default='cave_map.pdf')
    args = parser.parse_args()

    points, colors, segments, comments = read_ply(args.filepath)
    meta = parse_header_metadata(comments)
    centerline_pts, wall_pts, centre_segments = segment_pointcloud(points, colors, segments)

    if len(centerline_pts) == 0:
        raise SystemExit("No centerline (yellow) vertices found in the cloud.")

    north_offset = meta['north_offset_deg']
    if north_offset is None:
        print("⚠️  No north_offset_deg in the header — the surveyor did not tap SET N.\n"
              "    Bearings below are in the arbitrary ARKit yaw frame, not compass bearings.")

    centre_e, centre_n = to_east_north(centerline_pts, north_offset)
    wall_e, wall_n = to_east_north(wall_pts, north_offset)

    # Depth runs on Y, not Z. The old code read column 2 (Z), which is horizontal,
    # so every depth it reported was a horizontal offset.
    origin_y = centerline_pts[0, 1]
    all_y = points[:, 1]
    max_depth = float(-(np.min(all_y) - origin_y))
    max_height = float(np.max(all_y) - origin_y)

    # 3D length, so vertical travel is not discarded on sloping passages, and
    # summed per tracking run so a gap is never counted as surveyed passage.
    runs = split_runs(centerline_pts, centre_segments)
    total_distance = 0.0
    for start, end in runs:
        if end - start > 1:
            leg = centerline_pts[start:end]
            total_distance += float(np.sum(np.linalg.norm(np.diff(leg, axis=0), axis=1)))

    # Overall trend, as a compass bearing when north is known.
    delta_e = centre_e[-1] - centre_e[0]
    delta_n = centre_n[-1] - centre_n[0]
    bearing = math.degrees(math.atan2(delta_e, delta_n)) % 360

    fig, axes = plt.subplots(1, 2, figsize=(16, 7))

    # --- Plan view: north up ---
    ax = axes[0]
    ax.scatter(wall_e, wall_n, s=0.5, color='gray', label='Walls')
    for i, (start, end) in enumerate(runs):
        ax.plot(centre_e[start:end], centre_n[start:end], color='goldenrod',
                label='Centerline' if i == 0 else None)
    if len(wall_pts) >= 4:
        plot_contour(ax, alpha_shape(np.column_stack([wall_e, wall_n]), alpha=args.alpha))
    ax.set_title("Plan View (north up)" if north_offset is not None
                 else "Plan View (arbitrary yaw — north not set)")
    ax.set_xlabel("East (m)")
    ax.set_ylabel("North (m)")
    ax.axis('equal')
    ax.legend()

    # --- Profile: best-fit vertical section through the passage ---
    axis = principal_axis(np.column_stack([centre_e, centre_n]))
    centre_s = centre_e * axis[0] + centre_n * axis[1]
    wall_s = wall_e * axis[0] + wall_n * axis[1]

    ax = axes[1]
    ax.scatter(wall_s, wall_pts[:, 1] - origin_y, s=0.5, color='gray', label='Walls')
    centre_h = centerline_pts[:, 1] - origin_y
    for i, (start, end) in enumerate(runs):
        ax.plot(centre_s[start:end], centre_h[start:end], color='goldenrod',
                label='Centerline' if i == 0 else None)
    if len(wall_pts) >= 4:
        plot_contour(ax, alpha_shape(
            np.column_stack([wall_s, wall_pts[:, 1] - origin_y]), alpha=args.alpha))
    ax.set_title("Profile (best-fit section along passage)")
    ax.set_xlabel("Distance along section (m)")
    ax.set_ylabel("Height above start (m)")
    ax.axis('equal')
    ax.legend()

    for vertex_index, text in meta['annotations'].items():
        if vertex_index < len(centerline_pts):
            axes[0].annotate(text, (centre_e[vertex_index], centre_n[vertex_index]),
                             fontsize=7, color='darkred',
                             xytext=(4, 4), textcoords='offset points')

    accuracy = meta['north_accuracy_deg']
    north_note = ""
    if north_offset is not None:
        north_note = f" | Trend {bearing:.0f}°"
        if accuracy is not None and accuracy >= 0:
            north_note += f" ±{accuracy:.0f}° ({meta['north_reference'] or 'magnetic'})"

    gap_note = f" | {len(runs) - 1} tracking gap(s)" if len(runs) > 1 else ""
    fig.suptitle(
        f"Cave Map | Length {total_distance:.2f} m | "
        f"Depth {max_depth:.2f} m | Height +{max_height:.2f} m{north_note}{gap_note}",
        fontsize=14, fontweight='bold')

    if north_offset is not None:
        inset = fig.add_axes([0.075, 0.755, 0.075, 0.075])
        inset.set_xlim(-1.5, 1.5)
        inset.set_ylim(-1.5, 1.5)
        inset.axis('off')
        inset.set_aspect('equal')
        # The plan view is drawn north-up, so the needle points straight up.
        inset.add_patch(FancyArrow(0, 0, 0, 1, width=0.05, head_width=0.2,
                                   head_length=0.3, color='red'))
        inset.text(0, 1.25, "N", color='red', ha='center', va='center',
                   fontsize=10, fontweight='bold')

    plt.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(args.out, format="pdf")
    print(f"Length {total_distance:.2f} m, depth {max_depth:.2f} m, trend {bearing:.0f}°")
    print(f"Wrote {args.out}")
    plt.show()


if __name__ == "__main__":
    main()
