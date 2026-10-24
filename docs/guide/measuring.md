<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Measuring

All geodesy here is on a sphere of radius `EARTH_RADIUS` (6,371,008.8 m, the
IUGG mean radius R1), not on the WGS 84 ellipsoid. Distances are in metres,
angles in degrees, bearings clockwise from true north.

## Distance and bearing

```jennifer
def innsbruck as geo.Point init geo.point(47.2692, 11.4041);
def vienna as geo.Point init geo.point(48.2082, 16.3738);

geo.distance($innsbruck, $vienna);   # 385943.7 metres
geo.bearing($innsbruck, $vienna);    # 72.5 degrees
```

`distance` (and `haversine`, which takes four bare coordinates in the order
`aLat, aLon, bLat, bLon`) uses the haversine formula. The spherical model
differs from the ellipsoidal distance (as Vincenty's formulae compute it) by
typically 0.3 percent and at most about 0.5 percent; on a track's short legs
that is far below the error of a consumer GPS fix. Haversine is used rather than the spherical law of cosines because the
`acos` in the latter is ill-conditioned for short legs, and a track log is
mostly legs of a few metres.

`bearing` is the initial heading, `finalBearing` the heading on arrival; on a
great circle they differ. Both return 0 <= result < 360, and 0 for two equal
points. `destination` walks a bearing for a distance and `midpoint` halves a
leg, both along the great circle:

```jennifer
def there as geo.Point init geo.destination($innsbruck, 72.5, 385943.7);
```

`testDestinationAndBearingAreInverses` asserts that `destination` and
`bearing` invert each other. Longitudes that `destination` carries past 180
degrees wrap into -180..180. `toRadians` and `toDegrees` convert angles.

Jennifer raises on an undefined result instead of returning NaN, and for two
points a few centimetres apart rounding can push an `acos`, `asin` or `sqrt`
argument slightly out of its domain. Every such argument is clamped first, so
the near-identical fixes of a GPS waiting at a traffic light measure instead of
raising.

## Path and track length

```jennifer
geo.pathLength($points);        # leg by leg along a list
geo.trackDistance($track);      # per segment, summed
```

`pathLength` of fewer than two points is 0. For a track use `trackDistance`:
`pathLength(trackPoints($t))` counts the gap where the recorder lost its fix as
distance travelled (`testTrackDistanceDoesNotBridgeASegmentGap`).

## Statistics

```jennifer
def s as geo.TrackStats init geo.statsOf($points);
```

`statsOf` measures one list of points as one continuous path. Called on
`trackPoints` of a multi-segment track, its `distance` includes the gaps
between segments; measure per segment, or take the distance from
`trackDistance`.

`distance` sums every leg. Points with no elevation are skipped for the
elevation fields; with none at all, those fields are 0 and `hasElevation` is
false. Timing needs at least two points whose `at` parses, the last no earlier
than the first; otherwise the time and speed fields are 0 and `hasTime` is
false. A route planned on a map therefore reports its distance and nothing
else.

### Climb threshold

An altimeter, barometric or GPS, wanders a few metres while standing still.
Summing every upward step counts that wander, which can give a flat ride
several hundred metres of ascent.

`ASCENT_THRESHOLD` is 3.0 m. Ascent and descent are measured against a
reference elevation, starting at the first point that has one: a point at least the
threshold above the reference adds the difference to `ascent` and becomes the
new reference, and the same downwards for `descent`. Wander smaller than the
threshold never moves the reference, while a slow climb of 1 m steps still
counts once it has risen 3 m.

`statsWith` takes the climb threshold (metres) and the moving speed (m/s) as
arguments, and raises if either is negative:

```jennifer
def raw as geo.TrackStats init geo.statsWith($points, 0.0, geo.MOVING_SPEED);
```

[`examples/measure.j`](https://github.com/deckyard/deck-geo/blob/main/examples/measure.j)
prints both totals over the same track.

### Moving time

`MOVING_SPEED` is 0.5 m/s, about 1.8 km/h: slower than walking, faster than a
stationary fix drifts. A timed leg slower than that does not count towards
`movingSeconds`, and `averageSpeed` is `distance` over moving time, not over
elapsed time. `maxSpeed` is the fastest timed leg, in m/s.

`movingSeconds` never exceeds `totalSeconds`, even when timestamps run
backwards (a recorder whose clock stepped, or two files concatenated); a leg
whose time does not increase is not timed. Legs are timed to the millisecond
and the totals rounded to the second, so a logger writing several fixes per
second is measured correctly. A timestamp with no zone is read as UTC.

`secondsBetween(from, to2)` is the same parsing on its own: the difference in
whole seconds (rounded), or -1 when either stamp does not parse.

## Simplification

```jennifer
def thin as list of geo.Point init geo.simplify($points, 10.0);
```

Ramer-Douglas-Peucker. The two ends are kept; within each span, the point
furthest from the straight segment joining the span's ends is kept if it lies
more than `tolerance` metres from it, and the span is split there. Kept points
come back whole, with elevation, time and name. Paths of fewer than three
points are returned unchanged; a negative tolerance raises.

The offset is computed on a local plane (longitude scaled by the cosine of
latitude, taken the short way across the antimeridian), which agrees with the
spherical answer to well under a millimetre at tolerance distances.

A smooth recorded track thins hard: a 20,000-point hour-long ride comes back
as 61 points at 10 m and draws the same at map scale.

Cost depends on shape: about O(n log n) on a smooth track, O(n squared) in the
worst case, a path that deviates from every chord (a random walk, or GPS noise
with no route underneath). A 50,000-point track of mostly noise takes a long
time and keeps most of its points.

`crossTrackDistance(p, a, b)` answers a different question: how far `p` lies
from the great circle through `a` and `b`, which is a navigator's off-course
distance. It measures to the infinite great circle, so a point beyond the end
of the leg still gets a distance from the course line. When `a` and `b` are
the same point it returns the distance from `a` to `p`.

## Resampling

`resample` emits a point every `spacing` metres along the path, interpolated
along the leg it falls on, plus the original first and last points:

```jennifer
def even as list of geo.Point init geo.resample($points, 100.0);
```

Use it for an elevation profile, where the uneven spacing of GPS samples
distorts the chart. Interpolated points carry coordinates, and an elevation
when both ends of their leg had one; they have no time and no name. A spacing
that is not positive raises.

`interpolate(a, b, fraction)` is the step on its own. It works in degrees,
which over one leg of a track is indistinguishable from the great circle, and
takes longitude the short way, so a leg across the antimeridian stays near it.
A fraction outside 0.0..1.0 extrapolates instead of clamping; longitude wraps,
and a latitude pushed past the poles raises.

## Geofencing

```jennifer
if (geo.pointInPolygon($fix, $fence)) {
    alert();
}
```

Even-odd ray casting over a polygon given as its vertices, in plain degrees.
The ring closes implicitly, so a KML `LinearRing` or a GeoJSON ring works
whether or not it repeats its first vertex. Concave shapes work; fewer than
three vertices raises. A point exactly on an edge can come back either way.
Longitudes are not unwrapped, so a polygon that crosses the antimeridian is
not handled.

`containsPoint` against a `Bounds` is a rectangle test, edges included, and a
cheap pre-filter.
