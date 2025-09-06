import { db } from "../utils/firebase.js";
import { legacyScraperConfigs } from "../legacy-scrapers/configs.js";

const usersRef = db.collection("users");

/**
 * Verify that all legacy scraper venues exist in the database
 */
export async function verifyVenueUsernames(): Promise<void> {
  console.log("🔍 Verifying venue usernames in database...");

  let foundVenues = 0;
  let missingVenues = 0;
  const missingVenuesList: string[] = [];

  for (const config of legacyScraperConfigs) {
    console.log(`\n📍 Checking venue: ${config.name} (${config.username})`);

    try {
      // Check by username
      const usernameQuery = await usersRef
        .where("username", "==", config.username)
        .limit(1)
        .get();

      if (!usernameQuery.empty) {
        const venueDoc = usernameQuery.docs[0];
        const venueData = venueDoc.data();
        console.log(
          `  ✅ Found by username: ${venueData.artistName || venueData.username}`,
        );
        console.log(`     ID: ${venueDoc.id}`);
        console.log(`     Expected ID: ${config.id}`);

        if (venueDoc.id === config.id) {
          console.log("     ✅ ID matches config");
        } else {
          console.log("     ⚠️  ID mismatch - config may need updating");
        }

        foundVenues++;
        continue;
      }

      // Check by ID directly
      const idDoc = await usersRef.doc(config.id).get();
      if (idDoc.exists) {
        const venueData = idDoc.data();
        console.log(
          `  ✅ Found by ID: ${venueData?.artistName || venueData?.username}`,
        );
        console.log(`     Username in DB: ${venueData?.username}`);
        console.log(`     Expected username: ${config.username}`);

        if (venueData?.username === config.username) {
          console.log("     ✅ Username matches config");
        } else {
          console.log("     ⚠️  Username mismatch - config may need updating");
        }

        foundVenues++;
        continue;
      }

      // Not found by either method
      console.log("  ❌ Venue not found in database");
      console.log(`     Searched for username: ${config.username}`);
      console.log(`     Searched for ID: ${config.id}`);
      missingVenues++;
      missingVenuesList.push(`${config.name} (${config.username})`);
    } catch (error) {
      console.error(`  💥 Error checking venue: ${error}`);
      missingVenues++;
      missingVenuesList.push(`${config.name} (${config.username}) - ERROR`);
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log("📊 VERIFICATION SUMMARY");
  console.log("=".repeat(60));
  console.log(`Total venues checked: ${legacyScraperConfigs.length}`);
  console.log(`✅ Found venues: ${foundVenues}`);
  console.log(`❌ Missing venues: ${missingVenues}`);

  if (missingVenues > 0) {
    console.log("\n🚨 MISSING VENUES:");
    missingVenuesList.forEach((venue) => console.log(`   - ${venue}`));
    console.log("\n💡 Next steps:");
    console.log("   1. Check if usernames in config are correct");
    console.log("   2. Verify venue documents exist in Firestore");
    console.log("   3. Update config with correct usernames/IDs");
  } else {
    console.log("\n🎉 All venues verified successfully!");
  }
}

/**
 * Search for venues by partial username match
 */
export async function searchVenuesByName(searchTerm: string): Promise<void> {
  console.log(`🔍 Searching for venues containing: "${searchTerm}"`);

  try {
    const querySnapshot = await usersRef
      .where("username", ">=", searchTerm)
      .where("username", "<=", searchTerm + "\uf8ff")
      .limit(10)
      .get();

    if (querySnapshot.empty) {
      console.log("❌ No venues found with that search term");
      return;
    }

    console.log(`\n📋 Found ${querySnapshot.size} matching venues:`);
    querySnapshot.docs.forEach((doc, index) => {
      const data = doc.data();
      console.log(`\n${index + 1}. ${data.artistName || data.username}`);
      console.log(`   ID: ${doc.id}`);
      console.log(`   Username: ${data.username}`);
      console.log(`   Email: ${data.email}`);
      if (data.venueInfo) {
        console.log("   Venue: Yes");
        console.log(`   Website: ${data.venueInfo.websiteUrl || "N/A"}`);
      }
    });
  } catch (error) {
    console.error(`💥 Error searching venues: ${error}`);
  }
}

/**
 * List all venue usernames that contain common venue-related terms
 */
export async function listPotentialVenues(): Promise<void> {
  console.log("🔍 Searching for potential venue accounts...");

  const venueTerms = [
    "club",
    "bar",
    "venue",
    "theater",
    "theatre",
    "hall",
    "room",
    "house",
    "pub",
    "lounge",
    "cafe",
    "coffee",
    "music",
    "live",
    "brooklyn",
    "nyc",
    "dc",
    "richmond",
    "virginia",
    "washington",
  ];

  const foundVenues = new Set<string>();

  for (const term of venueTerms) {
    try {
      const querySnapshot = await usersRef
        .where("username", ">=", term)
        .where("username", "<=", term + "\uf8ff")
        .limit(5)
        .get();

      querySnapshot.docs.forEach((doc) => {
        const data = doc.data();
        if (data.venueInfo || data.username.includes(term)) {
          foundVenues.add(
            `${data.username} (${doc.id}) - ${data.artistName || "No name"}`,
          );
        }
      });
    } catch (error) {
      console.error(`Error searching for "${term}": ${error}`);
    }
  }

  console.log(`\n📋 Found ${foundVenues.size} potential venues:`);
  Array.from(foundVenues)
    .sort()
    .forEach((venue, index) => {
      console.log(`${index + 1}. ${venue}`);
    });
}

/**
 * CLI interface
 */
async function main() {
  const command = process.argv[2];
  const searchTerm = process.argv[3];

  try {
    switch (command) {
    case "verify":
      await verifyVenueUsernames();
      break;
    case "search":
      if (!searchTerm) {
        console.error("Usage: npm run verify-venues search <search_term>");
        process.exit(1);
      }
      await searchVenuesByName(searchTerm);
      break;
    case "list":
      await listPotentialVenues();
      break;
    default:
      console.log("Usage:");
      console.log(
        "  npm run verify-venues verify  - Verify all legacy venue usernames",
      );
      console.log(
        "  npm run verify-venues search <term>  - Search for venues by name",
      );
      console.log(
        "  npm run verify-venues list    - List all potential venue accounts",
      );
      break;
    }
  } catch (error) {
    console.error("💥 Script failed:", error);
    process.exit(1);
  }
}

main().catch(console.error);
