(async () => {
    const worlds = {
        1: "tamriel_rebuilt",
        2: "province_cyrodiil",
        3: "skyrim_home_of_the_nords"
    };

    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

    for (const [world, name] of Object.entries(worlds)) {
        const url = `/ptr/db/gamemap.php?action=get_locs&world=${world}&db=ptr`;
        console.log(`Downloading ${name}...`);

        const response = await fetch(url, {
            credentials: "same-origin",
            cache: "no-store"
        });

        if (!response.ok) {
            throw new Error(`${name}: HTTP ${response.status}`);
        }

        const contentType = response.headers.get("content-type") || "";
        if (!contentType.includes("json")) {
            const text = await response.text();
            console.error(`${name}: expected JSON but received:`, text.slice(0, 500));
            throw new Error(`${name}: response was not JSON`);
        }

        const data = await response.json();

        data._metadata = {
            world_id: Number(world),
            world_name: name,
            retrieved_at: new Date().toISOString(),
            source: url
        };

        const blob = new Blob(
            [JSON.stringify(data, null, 2)],
            { type: "application/json" }
        );

        const link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = `${name}.json`;
        link.click();
        URL.revokeObjectURL(link.href);

        console.log(
            `${name}: saved ${data.locations?.length ?? 0} locations`
        );

        await sleep(5000);
    }

    console.log("All three worlds downloaded.");
})();
