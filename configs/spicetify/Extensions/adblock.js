//@ts-check

// NAME: adblock
// AUTHOR: CharlieS1103 (Refactored & Enhanced)
// DESCRIPTION: Block all audio and UI ads on Spotify with auto-mute fallback, statistics, and Popup Modal settings
// LOCAL EDIT vs upstream 6e4c8cdd:
//   - emoji stripped from stat labels and toasts
//   - UI moved to the "adblock" custom app (Marketplace-style nav entry), so the
//     legacy topbar button and modal are gone
//   - ad slot layer: subscribe to every slot, clearSlot() each ad as it opens, and
//     repoint that slot's ad server (adsCoreConnector.updateAdServerEndpoint)
//   - Cosmos playtime override, in-stream ad API disabled, detection widened and polled
//     while playing, and engine status published for the app page. The premium/product
//     -state spoof alone is a no-op on this client, hence the slot layer.

/// <reference path="../../spicetify-cli/globals.d.ts" />

(function adblock() {
    if (!Spicetify.Platform) {
        setTimeout(adblock, 300);
        return;
    }

    const { Platform } = Spicetify;

    // --- State and Stats Setup ---
    let isAdblockEnabled = localStorage.getItem("adblock-enabled") !== "false";
    let blockedStats = {
        audio: parseInt(localStorage.getItem("adblock-stats-audio") || "0", 10),
        billboard: parseInt(localStorage.getItem("adblock-stats-billboard") || "0", 10),
        ui: parseInt(localStorage.getItem("adblock-stats-ui") || "0", 10)
    };
    let wasMutedByAdblock = false;

    function saveStats() {
        localStorage.setItem("adblock-stats-audio", blockedStats.audio.toString());
        localStorage.setItem("adblock-stats-billboard", blockedStats.billboard.toString());
        localStorage.setItem("adblock-stats-ui", blockedStats.ui.toString());
    }

    function incrementBlocked(type) {
        blockedStats[type] += 1;
        saveStats();
    }

    function showNotification(message) {
        if (typeof Spicetify.Toast?.show === 'function') {
            Spicetify.Toast.show(message);
        } else if (typeof Spicetify.showNotification === 'function') {
            Spicetify.showNotification(message);
        } else {
            console.log("[Adblock Toast]", message);
        }
    }

    // --- Dynamic CSS Injection ---
    const styleSheet = document.createElement("style");
    styleSheet.id = "adblock-styles";
    styleSheet.innerHTML = `
    .MnW5SczTcbdFHxLZ_Z8j, .WiPggcPDzbwGxoxwLWFf, .ReyA3uE3K7oEz7PTTnAn, .main-leaderboardComponent-container, .sponsor-container, a.link-subtle.main-navBar-navBarLink.GKnnhbExo0U9l7Jz2rdc, button[title="Upgrade to Premium"], button[aria-label="Upgrade to Premium"], .main-topBar-UpgradeButton, .main-contextMenu-menuItem a[href^="https://www.spotify.com/premium/"] {
        display: none !important;
    }
    `;
    document.body.appendChild(styleSheet);

    function updateStylesState() {
        styleSheet.disabled = !isAdblockEnabled;
    }
    updateStylesState();

    // --- Smart Dynamic UI Cleaner ---
    function cleanUI() {
        if (!isAdblockEnabled) return;

        let cleanedCount = 0;

        const upgradeSelectors = [
            'button[title*="Upgrade"]',
            'button[aria-label*="Upgrade"]',
            'a[href*="spotify.com/premium"]',
            '.main-topBar-UpgradeButton'
        ];

        upgradeSelectors.forEach(selector => {
            const elements = document.querySelectorAll(selector);
            elements.forEach((el) => {
                if (el.style.display !== 'none') {
                    el.style.display = 'none';
                    cleanedCount++;
                }
            });
        });

        const menuItems = document.querySelectorAll('li');
        menuItems.forEach((item) => {
            if (item.textContent && (item.textContent.includes("Upgrade to Premium") || item.textContent.includes("Premium"))) {
                const link = item.querySelector('a[href*="spotify.com/premium"]');
                if (link && item.style.display !== 'none') {
                    item.style.display = 'none';
                    cleanedCount++;
                }
            }
        });

        if (cleanedCount > 0) {
            blockedStats.ui += cleanedCount;
            saveStats();
        }
    }

    const uiObserver = new MutationObserver(() => {
        cleanUI();
    });
    uiObserver.observe(document.body, {
        childList: true,
        subtree: true
    });

    // --- Hook Billboard Ads ---
    const adManagers = Platform.AdManagers;
    if (adManagers?.billboard?.displayBillboard) {
        const billboard = adManagers.billboard.displayBillboard;

        adManagers.billboard.displayBillboard = function (...args) {
            if (!isAdblockEnabled) {
                return billboard.apply(this, args);
            }

            try {
                adManagers.billboard.finish();
                incrementBlocked("billboard");
            } catch (e) {
                console.warn("[Adblock] Failed to finish billboard early:", e);
            }

            const ret = billboard.apply(this, args);

            try {
                adManagers.billboard.finish();
            } catch (e) {
                console.warn("[Adblock] Failed to finish billboard late:", e);
            }

            const observer = new MutationObserver((_, obs) => {
                const billboardAd = document.getElementById('view-billboard-ad');
                if (billboardAd) {
                    try {
                        adManagers.billboard.finish();
                    } catch (e) {
                        console.warn("[Adblock] Failed to finish billboard on mutation:", e);
                    }
                    obs.disconnect();
                }
            });

            observer.observe(document, {
                childList: true,
                subtree: true
            });

            setTimeout(() => {
                observer.disconnect();
            }, 10000);

            return ret;
        };
    }

    // --- Engine status (surface on the Adblock page) ---
    // The premium/product-state override this extension was built around is a no-op on
    // current clients, so publish what actually engaged instead of implying success.
    const AD_SERVER_SINK = "http://localhost/adblock-no-ads";
    const engineStatus = {
        adsOverrideEffective: null,
        adServerRedirected: false,
        adServerSink: AD_SERVER_SINK,
        audioManagerDisabled: null,
        inStreamApiDisabled: null,
        updatedAt: 0
    };

    function publishStatus() {
        engineStatus.updatedAt = Date.now();
        try {
            localStorage.setItem("adblock-status", JSON.stringify(engineStatus));
        } catch (e) {
            console.warn("[Adblock] status write failed:", e);
        }
    }

    // putOverridesValues resolves even when the client ignores the override, so read
    // the value back rather than trusting the promise.
    async function readAdsOverride(productState) {
        if (!productState || typeof productState.getValues !== "function") return null;
        const readAds = async (args) => {
            const values = args === undefined ? await productState.getValues() : await productState.getValues(args);
            const ads = values && values.pairs ? values.pairs.ads : undefined;
            return ads === undefined ? null : ads === "0";
        };
        try {
            const scoped = await readAds({ keys: ["ads"] });
            if (scoped !== null) return scoped;
        } catch (e) { /* fall through to the unkeyed read */ }
        try {
            return await readAds();
        } catch (e) {
            return null;
        }
    }

    // Ad slot ids on this client build. Subscribing to an id the build does not know
    // is harmless, so this is a superset of the ad manager names.
    const AD_SLOT_IDS = [
        "audio", "vto", "leaderboard", "home", "survey",
        "inStreamApi", "embeddedAd", "embeddedPlaylist",
        "billboard", "sponsoredPlaylist"
    ];

    function clearAdSlot(connector, slotId) {
        try {
            connector.clearSlot(slotId);
            engineStatus.slotsCleared = (engineStatus.slotsCleared || 0) + 1;
        } catch (e) {
            console.warn("[Adblock] clearSlot failed for " + slotId + ":", e);
        }
    }

    // Subscribe to every slot, clear ads the moment a slot opens, and point that slot's
    // ad server at a dead local endpoint so nothing can be fetched for it.
    async function configureAdSlots(inStreamApi) {
        const connector = inStreamApi?.adsCoreConnector;
        if (!connector) return;

        let subscribed = 0;
        let redirected = 0;
        let redirectError = null;

        for (const slotId of AD_SLOT_IDS) {
            try {
                const result = connector.subscribeToSlot(slotId, (data) => {
                    const id = (data && data.adSlotEvent && data.adSlotEvent.slotId) || slotId;
                    clearAdSlot(connector, id);
                    publishStatus();
                });
                // Unknown slot ids reject; never leave that unhandled.
                if (result && typeof result.catch === "function") result.catch(() => {});
                subscribed += 1;
            } catch (e) {
                // Expected for ids this build does not serve.
            }

            try {
                // Signature is positional: (slotIds, url).
                await connector.updateAdServerEndpoint([slotId], AD_SERVER_SINK);
                redirected += 1;
            } catch (e) {
                if (!redirectError) redirectError = String((e && e.message) || e);
            }
        }

        engineStatus.slotsSubscribed = subscribed;
        engineStatus.slotsRedirected = redirected;
        engineStatus.adServerRedirected = redirected > 0;
        if (redirectError) engineStatus.adServerRedirectError = redirectError;
    }

    // --- Fallback Audio Ad Auto-Mute & Auto-Skip ---
    // Free-tier ads arrive as interleaved tracks, so songchange alone can miss them;
    // detection is shared and re-checked on a timer as well.
    function currentTrackIsAd() {
        const track = Spicetify.Player?.data?.track;
        if (!track) return false;
        if (track.metadata?.is_advertisement === "true") return true;
        if (track.metadata?.ad_id) return true;
        if (typeof track.uri === "string" && track.uri.includes("spotify:ad:")) return true;

        // The client's own ad pipelines report a live ad even when metadata is bare.
        const inStream = Platform.AdManagers?.audio?.inStreamApi;
        try {
            if (inStream && inStream.inStreamAd) return true;
        } catch (e) { /* ignore */ }
        try {
            const context = Platform.AdManagers?.audio?.getContextAdInfo?.();
            if (context && (context.isAd || context.adId || context.ad_id)) return true;
        } catch (e) { /* ignore */ }
        return false;
    }

    function handleTrackChange() {
        if (!isAdblockEnabled) return;
        if (!Spicetify.Player?.data?.track) return;

        const isAd = currentTrackIsAd();

        if (isAd) {
            if (!wasMutedByAdblock) {
                try {
                    Spicetify.Player.setMute(true);
                    wasMutedByAdblock = true;
                } catch (e) {
                    console.error("[Adblock] Failed to mute player:", e);
                }
            }
            try {
                Spicetify.Player.next();
                incrementBlocked("audio");
                showNotification("Adblock: Muted & Skipped Audio Ad!");
            } catch (e) {
                console.error("[Adblock] Failed to skip ad:", e);
            }
        } else {
            if (wasMutedByAdblock) {
                try {
                    Spicetify.Player.setMute(false);
                    wasMutedByAdblock = false;
                } catch (e) {
                    console.error("[Adblock] Failed to unmute player:", e);
                }
            }
        }
    }

    if (Spicetify.Player) {
        Spicetify.Player.addEventListener("songchange", handleTrackChange);
    }

    // Short ads can start and finish between songchange events.
    setInterval(() => {
        if (Spicetify.Player?.isPlaying) handleTrackChange();
    }, 1000);

    // --- Active Adblock Core ---
    async function delayAds() {
        if (!isAdblockEnabled) return;
        if (!Platform.UserAPI) {
            setTimeout(delayAds, 300);
            return;
        }

        try {
            const productState = Platform.UserAPI._product_state || Platform.UserAPI._product_state_service;
            if (productState && typeof productState.putOverridesValues === 'function') {
                await productState.putOverridesValues({
                    pairs: {
                        ads: "0",
                        catalogue: "premium",
                        product: "premium",
                        type: "premium"
                    }
                });
            }

            engineStatus.adsOverrideEffective = await readAdsOverride(productState);

            const am = Platform.AdManagers;
            if (am) {
                // Slot layer, following rxri/adblockify + spadblocker: the premium spoof is
                // a no-op on current clients, so clear ad slots as they open and repoint
                // the per-slot ad server instead.
                await configureAdSlots(am.audio?.inStreamApi);

                // Ask the ads backend for a stream time far in the past so it considers any
                // pending ad slot already played (same trick adblockify uses).
                if (Spicetify.CosmosAsync && typeof Spicetify.CosmosAsync.post === "function") {
                    try {
                        await Spicetify.CosmosAsync.post("sp://ads/v1/testing/playtime", { value: -100000000000 });
                    } catch (e) {
                        console.warn("[Adblock] playtime override failed:", e);
                    }
                }

                if (am.audio?.audioApi?.cosmosConnector) {
                    try {
                        am.audio.audioApi.cosmosConnector.increaseStreamTime(-100000000000);
                    } catch (e) {
                        console.warn("[Adblock] increaseStreamTime audio failed:", e);
                    }
                }
                if (am.billboard?.billboardApi?.cosmosConnector) {
                    try {
                        am.billboard.billboardApi.cosmosConnector.increaseStreamTime(-100000000000);
                    } catch (e) {
                        console.warn("[Adblock] increaseStreamTime billboard failed:", e);
                    }
                }

                // disable() is not guaranteed to return a promise in every client build,
                // so never chain .catch() on its result - a non-promise return would throw
                // and skip the rest of this block.
                const disableOne = async (label, fn) => {
                    if (typeof fn !== "function") return;
                    try {
                        await fn();
                    } catch (e) {
                        console.warn("[Adblock] disable " + label + " failed:", e);
                    }
                };

                if (am.audio) await disableOne("audio", am.audio.disable?.bind(am.audio));
                if (am.billboard) await disableOne("billboard", am.billboard.disable?.bind(am.billboard));
                if (am.leaderboard) await disableOne("leaderboard", am.leaderboard.disableLeaderboard?.bind(am.leaderboard));
                if (am.sponsoredPlaylist) await disableOne("sponsoredPlaylist", am.sponsoredPlaylist.disable?.bind(am.sponsoredPlaylist));
                if (am.audio?.inStreamApi) await disableOne("inStreamApi", am.audio.inStreamApi.disable?.bind(am.audio.inStreamApi));

                engineStatus.audioManagerDisabled = am.audio ? am.audio.enabled === false : null;
                engineStatus.inStreamApiDisabled = am.audio?.inStreamApi ? am.audio.inStreamApi.enabled === false : null;
            }

        } catch (error) {
            console.error("[Adblock] Error during disabling ads:", error);
        } finally {
            // Always publish, even if one primitive threw, so the page reflects reality.
            publishStatus();
        }
    }

    delayAds();
    setInterval(delayAds, 30 * 1000);

    (async function subscribeToProductState() {
        if (!Platform.UserAPI) {
            setTimeout(subscribeToProductState, 300);
            return;
        }
        try {
            const productState = Platform.UserAPI._product_state || Platform.UserAPI._product_state_service;
            if (productState && typeof productState.subValues === 'function') {
                productState.subValues({ keys: ["ads"] }, () => {
                    delayAds();
                });
            }
        } catch (e) {
            console.log("[Adblock] Product State subscribe failed:", e);
        }
    })();

    // --- Custom app control surface (Spotify > Adblock) ---
    // Blocking state lives here. The adblock page is a spicetify custom app with no
    // state of its own: it mirrors localStorage and pokes the engine via these events.
    window.addEventListener("adblock:set-enabled", (event) => {
        isAdblockEnabled = event.detail !== false;
        localStorage.setItem("adblock-enabled", isAdblockEnabled ? "true" : "false");
        updateStylesState();
        if (isAdblockEnabled) delayAds();
    });

    window.addEventListener("adblock:reset-stats", () => {
        blockedStats = { audio: 0, billboard: 0, ui: 0 };
        saveStats();
    });

})();
