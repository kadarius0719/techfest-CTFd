/**
 * ================================================================
 * THE SOURCE MAP TREASURE
 * ================================================================
 * You found it! Not many people dig through source maps.
 * That takes real dedication to the craft.
 *
 * Flag: TECHFEST{source_maps_reveal_developer_secrets}
 *
 * This file is intentionally included in the build to reward
 * players who explore the source maps of the compiled assets.
 * ================================================================
 */

// Side-effect: register a hidden property on window (won't show in console)
Object.defineProperty(window, '__arcade_treasure', {
  value: 'Look at this file in the source map',
  enumerable: false,
  configurable: false
});
