/** Geographic helpers for discovery: distances, boxes and city grid tiling. Pure functions, no I/O. */
import type { BoundingBox, LatLng } from "../types.js";

const EARTH_RADIUS_M = 6_371_008.8;
const METERS_PER_DEGREE_LAT = 111_320;

const rad = (deg: number) => (deg * Math.PI) / 180;

/** Great-circle distance in meters. */
export function haversineMeters(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Distance between two possibly-unknown points; null when either side lacks coordinates. */
export function distanceOrNull(
  a: { lat: number | null; lng: number | null },
  b: { lat: number | null; lng: number | null },
): number | null {
  if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) return null;
  return haversineMeters({ lat: a.lat, lng: a.lng }, { lat: b.lat, lng: b.lng });
}

function metersPerDegreeLng(lat: number): number {
  return METERS_PER_DEGREE_LAT * Math.max(Math.cos(rad(lat)), 0.01);
}

/** Axis-aligned box that contains the circle (center, radius). */
export function bboxAround(center: LatLng, radiusMeters: number): BoundingBox {
  const dLat = radiusMeters / METERS_PER_DEGREE_LAT;
  const dLng = radiusMeters / metersPerDegreeLng(center.lat);
  return { south: center.lat - dLat, west: center.lng - dLng, north: center.lat + dLat, east: center.lng + dLng };
}

export function bboxCenter(box: BoundingBox): LatLng {
  return { lat: (box.south + box.north) / 2, lng: (box.west + box.east) / 2 };
}

export function inBbox(point: { lat: number | null; lng: number | null }, box: BoundingBox): boolean {
  if (point.lat == null || point.lng == null) return false;
  return point.lat >= box.south && point.lat <= box.north && point.lng >= box.west && point.lng <= box.east;
}

/** City configuration for map-search discovery. */
export interface CityConfig {
  /** Display name, also used as the candidates' `city`. */
  name: string;
  bbox: BoundingBox;
  /** IANA timezone of the city (assigned to candidates found there). */
  timezone: string;
  /** Grid cell edge length. Default 2500 m. */
  cellMeters?: number;
}

export interface GridCell {
  /** Stable id, e.g. "nashville:3:4" (usable as a job dedupe key). */
  id: string;
  city: string;
  timezone: string;
  bbox: BoundingBox;
  center: LatLng;
  /** Radius of the circle circumscribing the cell. */
  radiusMeters: number;
}

export const DEFAULT_CELL_METERS = 2500;

/**
 * Tiles a city's bounding box into roughly square cells of `cellMeters`. Places Text Search returns at most 60
 * results per query, so dense downtowns need small cells; cells are clipped to the city box.
 */
export function cityGrid(city: CityConfig, cellMeters: number = city.cellMeters ?? DEFAULT_CELL_METERS): GridCell[] {
  if (!(cellMeters > 0)) throw new Error("cellMeters must be positive");
  const { south, west, north, east } = city.bbox;
  if (!(north > south) || !(east > west)) throw new Error(`Invalid bbox for ${city.name}`);
  const midLat = (south + north) / 2;
  const dLat = cellMeters / METERS_PER_DEGREE_LAT;
  const dLng = cellMeters / metersPerDegreeLng(midLat);
  const rows = Math.max(1, Math.ceil((north - south) / dLat - 1e-9));
  const cols = Math.max(1, Math.ceil((east - west) / dLng - 1e-9));
  const slug = city.name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  const cells: GridCell[] = [];
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const bbox: BoundingBox = {
        south: south + row * dLat,
        north: Math.min(north, south + (row + 1) * dLat),
        west: west + col * dLng,
        east: Math.min(east, west + (col + 1) * dLng),
      };
      const center = bboxCenter(bbox);
      const radiusMeters = haversineMeters(center, { lat: bbox.north, lng: bbox.east });
      cells.push({ id: `${slug}:${row}:${col}`, city: city.name, timezone: city.timezone, bbox, center, radiusMeters });
    }
  }
  return cells;
}
