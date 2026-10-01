#!/usr/bin/env node
/**
 * A stand-in for the alerts Worker, for designing and testing the alert states
 * without waiting for a real emergency. Development only - nothing in the app
 * imports this.
 *
 *   node scripts/mock-alerts.mjs            # http://localhost:8790/
 *   VITE_ALERTS_URL=http://localhost:8790/ npm run dev
 *
 * Switch scenario while the app is open (it re-polls every 2 minutes, and at
 * once when the tab regains focus):
 *
 *   curl localhost:8790/set/active      two alerts: Queens + citywide (default)
 *   curl localhost:8790/set/one         one Queens alert
 *   curl localhost:8790/set/three       three - the banner shows two and "View all 3 alerts"
 *   curl localhost:8790/set/withdrawn   'active' minus the police alert - it turns ended
 *   curl localhost:8790/set/nws         a Weather Service relay: lines, bullets, a scheme-less link
 *   curl localhost:8790/set/none        healthy, nothing active
 *   curl localhost:8790/set/unhealthy   feed_healthy: false  -> unavailable
 *   curl localhost:8790/set/down        HTTP 503             -> unavailable
 *
 * WHY A SERVER AND NOT A JSON FILE: the app treats a response more than 15
 * minutes old as unavailable, and drops alerts past `expires`. A static file
 * goes stale within a quarter of an hour. Every response here is stamped with
 * the current time, and each alert's sent/expires are relative to it.
 *
 * The alert text is real (data/archive/alerts, 2026-09-28/29), as the Worker's
 * CAP layer serves it. The NWS alert's scope is changed to 'queens' so it is
 * shown - the real one was Staten Island.
 */
import { createServer } from 'node:http';

const PORT = Number(process.env.PORT ?? 8790);
const MIN = 60_000;

const alert = (guid, minutesAgo, props) => ({
  type: 'Feature',
  geometry: null,
  properties: {
    id: guid,
    guid,
    translations_url: null,
    location: null,
    ...props,
    sent: new Date(Date.now() - minutesAgo * MIN).toISOString(),
    expires: new Date(Date.now() + (120 - minutesAgo) * MIN).toISOString(),
  },
});

const POLICE = () =>
  alert('2758435766629296', 9, {
    headline: 'Notify NYC - Police Activity - Cross Bay Boulevard (QN)',
    event: 'Police Activity',
    location: 'Cross Bay Boulevard',
    scope: 'queens',
    category: 'Safety',
    body: 'Due to police activity, expect traffic delays, road closures, mass transit disruptions and a heavy presence of emergency personnel in the area of the Cross Bay Boulevard and 165th Avenue in Queens. Use alternate routes to avoid the area and allow for additional travel time.',
  });
const WATERBODY = () =>
  alert('2751666898158459', 106, {
    headline: 'Notify NYC - Waterbody Advisory (NYC)',
    event: 'Waterbody Advisory',
    scope: 'citywide',
    category: 'Safety',
    body: 'Due to recent precipitation, waterbody advisories have been issued for waterways in your area. For more information and a list of impacted waterbodies, visit http://bit.ly/3KFvQQJ or call 3-1-1.',
    translations_url: 'http://on.nyc.gov/1OGVGMl',
  });
const FIRE = () =>
  alert('2754793634362080', 40, {
    headline: 'Notify NYC - Three Alarm Fire - Hillside Avenue (QN)',
    event: 'Three Alarm Fire',
    location: 'Hillside Avenue',
    scope: 'queens',
    category: 'Fire',
    body: 'Emergency personnel are on the scene of a three-alarm fire located at Hillside Avenue and 160th Street in Queens. Expect smoke, traffic delays, and a presence of emergency personnel and vehicles in the area.\n\nThe NYC Department of Health and Mental Hygiene advises avoiding smoke exposure from structural fires by closing windows while indoors and reducing outdoor activity where smoke is present. People with heart or breathing conditions such as asthma may be more sensitive and should seek immediate medical attention if they experience a worsening of their condition, shortness of breath, or chest pains.',
    translations_url: 'http://on.nyc.gov/1kdbhe2',
  });
const NWS = () =>
  alert('2755652627817500', 20, {
    headline: 'Notify NYC - Coastal Flood Statement - 9/29 (Staten Island)',
    event: 'Coastal Flood Statement',
    scope: 'queens',
    category: 'Geo',
    body: 'The National Weather Service has issued the following:\nWhat: Coastal Flood Statement\nWhere: Staten Island\nWhen: 9:00 AM on 9/29 to 12:00 Pm on 9/29\nHazards: Inundation of up to one half foot above ground level may cause minor flooding of shore roads and properties.\nPreparedness Actions:\n- Avoid driving through or coming in contact with flood waters. There could be pollutants in the water or other hazards that you cannot see.\n- Coastal flood waters could damage your vehicle. Move your car to higher ground and wash your car thoroughly if it makes contact with flood waters.\n- New York City residents, please call 311 if you encounter flooding that makes roads impassable, causes property damage, or persists for more than 48 hours.\n\nInfo: www.weather.gov/okx/.',
    translations_url: 'http://on.nyc.gov/2hoK0Ij',
  });

const SCENARIOS = {
  active: () => [POLICE(), WATERBODY()],
  one: () => [POLICE()],
  three: () => [POLICE(), FIRE(), WATERBODY()],
  withdrawn: () => [WATERBODY()],
  nws: () => [NWS()],
  none: () => [],
  unhealthy: 'unhealthy',
  down: 'down',
};
let scenario = process.argv[2] && SCENARIOS[process.argv[2]] ? process.argv[2] : 'active';

createServer((req, res) => {
  const cors = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' };
  const set = req.url.match(/^\/set\/(\w+)/);
  if (set) {
    if (!SCENARIOS[set[1]]) {
      res.writeHead(404, cors).end(`unknown scenario; one of ${Object.keys(SCENARIOS).join(', ')}\n`);
      return;
    }
    scenario = set[1];
    res.writeHead(200, cors).end(`scenario: ${scenario}\n`);
    return;
  }
  const s = SCENARIOS[scenario];
  if (s === 'down') {
    res.writeHead(503, { ...cors, 'Content-Type': 'application/json' }).end('{"error":"mock: down"}');
    return;
  }
  const features = typeof s === 'function' ? s() : [];
  res.writeHead(200, { ...cors, 'Content-Type': 'application/geo+json' }).end(
    JSON.stringify({
      type: 'FeatureCollection',
      generated_at: new Date().toISOString(),
      feed_healthy: s !== 'unhealthy',
      health_detail: s === 'unhealthy' ? 'english_missing' : null,
      features: s === 'unhealthy' ? [] : features,
    })
  );
}).listen(PORT, () => console.log(`mock alerts on http://localhost:${PORT}/ - scenario: ${scenario}`));
