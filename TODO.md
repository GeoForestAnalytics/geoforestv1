# Fixes for Scatter Chart Errors

## Issues to Fix:
1. [x] Replace `tooltipBgColor` with `getTooltipColor` function
2. [x] Fix `spotIndex` property access - track indices in ScatterSpot creation
3. [x] Update `getTooltipItems` function signature and return type
4. [x] Ensure proper data access for tooltips

## Steps:
1. [x] Modify scatterSpots creation to include index tracking
2. [x] Update ScatterTouchTooltipData configuration
3. [x] Fix tooltip function to use new API
4. [ ] Test compilation

## Progress:
- [x] Step 1: Track indices in scatter spots
- [x] Step 2: Update tooltip configuration
- [x] Step 3: Fix tooltip function
- [ ] Step 4: Verify fixes

## Changes Made:
- Replaced `tooltipBgColor` with `getTooltipColor: (_) => Colors.black`
- Fixed the tooltip function to properly find the index by comparing spot coordinates
- Updated the function to return a single `ScatterTooltipItem` instead of a list
