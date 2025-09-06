export function containsEventPath(url: string) {
  // Define a regular expression pattern to match any of the specified paths
  const eventPathRegex =
    /\/events\/|\/event\/|\/e\/|\/calendar\/|\/calendar-events\/|\/shows\/|\/upcoming\/|\/event-details\/|\/tm-event\/|\/happenings\/|\/events-1\/|\/find-a-show\/|\/EventDetail|\/upcomingevents\/|\/schedule\/|\/productions\/|\/listing\/|\/event-details-registration\/|\/concert\/|\/detalles-y-registro\/|\/music\/|\/list-of-events\/|\/tickets\/|\/eventsatmainline\/|\/ticketweb-more-info\//;

  // Test the URL path against the regular expression
  return eventPathRegex.test(url);
}

export function areSameDomain(url1: string, url2: string) {
  // Create URL objects
  const parsedUrl1 = new URL(url1);
  const parsedUrl2 = new URL(url2);

  // Extract hostname (domain) from URL objects
  const domain1 = getBaseDomain(parsedUrl1.hostname);
  const domain2 = getBaseDomain(parsedUrl2.hostname);

  return domain1 === domain2;
}

export function getBaseDomain(link: string) {
  const fullLink = link.trim().startsWith("http") ? link : `https://${link}`;
  const url = new URL(fullLink);
  const hostname = url.hostname;
  const parts = hostname.split(".").reverse();
  const topLevelDomain = parts[0];
  const secondLevelDomain = parts[1];

  // Check for country code top-level domains
  if (topLevelDomain.length === 2 && secondLevelDomain.length === 2) {
    return parts.slice(0, 3).reverse().join(".");
  }

  return parts.slice(0, 2).reverse().join(".");
}
