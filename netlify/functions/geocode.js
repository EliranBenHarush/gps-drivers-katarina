const https = require('https');

function httpsPost(hostname, path, headers, body) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method: 'POST', headers }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('parse: ' + data.slice(0, 200))); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function httpsGet(hostname, path, headers) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method: 'GET', headers }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('parse: ' + data.slice(0, 200))); }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

exports.handler = async function (event) {
  const q = (event.queryStringParameters && event.queryStringParameters.q) || '';
  if (!q) return { statusCode: 400, body: JSON.stringify([]) };

  const GOOGLE_KEY = process.env.GOOGLE_PLACES_KEY;
  if (!GOOGLE_KEY) return { statusCode: 500, body: JSON.stringify({ error: 'missing api key' }) };

  try {
    // Step 1: Autocomplete — works with partial queries
    const autocompleteJson = await httpsPost(
      'places.googleapis.com',
      '/v1/places:autocomplete',
      { 'Content-Type': 'application/json', 'X-Goog-Api-Key': GOOGLE_KEY },
      JSON.stringify({ input: q.trim(), includedRegionCodes: ['il'], languageCode: 'he' })
    );

    if (autocompleteJson.error) {
      return { statusCode: 502, body: JSON.stringify({ google_error: autocompleteJson.error }) };
    }

    const placeIds = (autocompleteJson.suggestions || [])
      .filter((s) => s.placePrediction)
      .map((s) => s.placePrediction.placeId)
      .slice(0, 5);

    if (placeIds.length === 0) {
      return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify([]) };
    }

    // Step 2: Place Details in parallel to get coordinates
    const details = await Promise.all(
      placeIds.map((id) =>
        httpsGet('places.googleapis.com', `/v1/places/${id}?languageCode=he`, {
          'X-Goog-Api-Key': GOOGLE_KEY,
          'X-Goog-FieldMask': 'formattedAddress,displayName,location',
        })
      )
    );

    const results = details
      .filter((d) => d.location)
      .map((d) => ({
        display_name: d.formattedAddress || d.displayName?.text || '',
        lon: String(d.location.longitude),
        lat: String(d.location.latitude),
      }));

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(results),
    };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ error: e.message }) };
  }
};
