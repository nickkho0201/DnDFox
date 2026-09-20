// ==UserScript==
// @name        Split View Drag Replace v2
// @description Drag an ordinary tab onto one pane of Firefox Split View
// @include     main
// @version     1.0.0
// @license     MIT
// ==/UserScript==

(() => {
  "use strict";

  const LOG_PREFIX = "[SplitView Drag Replace]";
  const SCRIPT_GUARD = "__splitViewDragReplaceLoaded";
  const MAX_RESTORE_FRAMES = 12;

  if (window[SCRIPT_GUARD]) {
    console.log(`${LOG_PREFIX} already loaded in this window`);
    return;
  }

  window[SCRIPT_GUARD] = true;

  let pendingSplitView = null;
  let pendingTab = null;

  let dragSplitView = null;
  let draggedTab = null;

  let highlightedBrowser = null;
  let splitRestoredForDrag = false;
  let operationGeneration = 0;
  let dragOperationId = 0;

  function getTabFromEvent(event) {
    for (const node of event.composedPath()) {
      if (
        node?.localName === "tab" &&
        node.classList?.contains("tabbrowser-tab")
      ) {
        return node;
      }
    }

    return null;
  }

  function splitContainsTab(splitView, tab) {
    return !!splitView?.tabs?.includes(tab);
  }

  function belongsToCurrentWindow(node) {
    // ownerDocument is the stable identity boundary for chrome DOM nodes.
    // ownerGlobal is not compared directly: for privileged/XUL objects Firefox
    // may expose a wrapper whose identity is not the ChromeWindow object.
    return !!node && node.ownerDocument === document;
  }

  function isCurrentTab(tab) {
    return !!tab?.isConnected && belongsToCurrentWindow(tab);
  }

  function isCurrentSplitView(splitView) {
    return !!splitView?.isConnected && belongsToCurrentWindow(splitView);
  }

  function resetNativeTabDragPresentation(tab) {
    try {
      const tabDragAndDrop =
        tab?.container?.tabDragAndDrop ||
        gBrowser?.tabContainer?.tabDragAndDrop;

      if (!tabDragAndDrop) {
        console.error(`${LOG_PREFIX} native tab drag cleanup is unavailable`);
        return;
      }

      // A normal tab-strip drop runs these before moving the tab. Our drop is
      // handled in the browser area, so do the same before replaceTab reparents
      // the dragged tab into the Split View wrapper.
      tabDragAndDrop.finishAnimateTabMove?.();
      tabDragAndDrop._resetTabsAfterDrop?.(tab);

      console.log(`${LOG_PREFIX} native tab drag presentation reset`);
    } catch (error) {
      console.error(
        `${LOG_PREFIX} native tab drag presentation reset failed:`,
        error
      );
    }
  }

  function clearHighlight() {
    if (!highlightedBrowser) {
      return;
    }

    highlightedBrowser.style.removeProperty("outline");
    highlightedBrowser.style.removeProperty("outline-offset");

    highlightedBrowser = null;
  }

  function highlightTab(tab) {
    const browser = tab?.linkedBrowser;

    if (!browser || browser === highlightedBrowser) {
      return;
    }

    clearHighlight();

    browser.style.setProperty(
      "outline",
      "3px solid AccentColor",
      "important"
    );

    browser.style.setProperty(
      "outline-offset",
      "-3px",
      "important"
    );

    highlightedBrowser = browser;
  }

  function captureSplitRatio(splitView) {
    if (!isCurrentSplitView(splitView)) {
      return null;
    }

    const leftTab = splitView.tabs?.[0];
    const tabpanels = gBrowser?.tabpanels;

    if (
      !isCurrentTab(leftTab) ||
      !leftTab.linkedPanel ||
      !tabpanels?.isConnected
    ) {
      return null;
    }

    const leftPanel = document.getElementById(leftTab.linkedPanel);

    if (!leftPanel?.isConnected || !belongsToCurrentWindow(leftPanel)) {
      return null;
    }

    const leftWidth = leftPanel.getBoundingClientRect().width;
    // Firefox 156 uses the full tabpanels width as the denominator for its
    // native Split View resize ratio telemetry.
    const containerWidth = tabpanels.getBoundingClientRect().width;

    if (
      !Number.isFinite(leftWidth) ||
      leftWidth <= 0 ||
      !Number.isFinite(containerWidth) ||
      containerWidth <= 0
    ) {
      return null;
    }

    const ratio = leftWidth / containerWidth;

    if (!Number.isFinite(ratio) || ratio <= 0 || ratio >= 1) {
      return null;
    }

    return ratio;
  }

  function restoreSplitRatio(splitView, expectedTab, ratio, operationId) {
    if (
      !splitView ||
      !expectedTab ||
      !Number.isFinite(ratio) ||
      ratio <= 0 ||
      ratio >= 1 ||
      !Number.isInteger(operationId) ||
      operationId <= 0
    ) {
      console.error(`${LOG_PREFIX} invalid split ratio restore request`);
      return;
    }

    let frameCount = 0;
    let lastWaitReason = "Firefox has not finished rebuilding Split View";

    const scheduleNextFrame = () => {
      requestAnimationFrame(tryRestore);
    };

    const retryOrFail = reason => {
      lastWaitReason = reason;

      if (frameCount >= MAX_RESTORE_FRAMES) {
        console.error(
          `${LOG_PREFIX} split ratio restore timed out after ${frameCount} frames:`,
          lastWaitReason
        );
        return;
      }

      scheduleNextFrame();
    };

    const tryRestore = () => {
      try {
        frameCount += 1;

        if (operationGeneration !== operationId) {
          console.log(
            `${LOG_PREFIX} skipped stale split ratio restore for operation`,
            operationId
          );
          return;
        }

        if (!isCurrentSplitView(splitView)) {
          retryOrFail("splitView is no longer connected to this window");
          return;
        }

        const splitTabs = splitView.tabs;

        if (!splitTabs?.includes(expectedTab)) {
          retryOrFail("dragged tab is not present in splitView.tabs");
          return;
        }

        if (!isCurrentTab(expectedTab) || !expectedTab.linkedPanel) {
          retryOrFail("dragged tab or its linkedPanel is not ready");
          return;
        }

        const expectedPanel = document.getElementById(expectedTab.linkedPanel);
        const leftTab = splitTabs[0];
        const rightTab = splitTabs[1];

        if (
          !expectedPanel?.isConnected ||
          !belongsToCurrentWindow(expectedPanel)
        ) {
          retryOrFail("new linkedPanel is not connected");
          return;
        }

        if (
          !isCurrentTab(leftTab) ||
          !isCurrentTab(rightTab) ||
          !leftTab.linkedPanel ||
          !rightTab.linkedPanel
        ) {
          retryOrFail("split view tabs are incomplete");
          return;
        }

        const leftPanel = document.getElementById(leftTab.linkedPanel);
        const rightPanel = document.getElementById(rightTab.linkedPanel);
        const tabpanels = gBrowser?.tabpanels;

        if (
          !leftPanel?.isConnected ||
          !rightPanel?.isConnected ||
          !belongsToCurrentWindow(leftPanel) ||
          !belongsToCurrentWindow(rightPanel) ||
          !tabpanels?.isConnected
        ) {
          retryOrFail("split view panels or container are not connected");
          return;
        }

        const containerRectWidth = tabpanels.getBoundingClientRect().width;
        const containerClientWidth = tabpanels.clientWidth;

        if (
          !Number.isFinite(containerRectWidth) ||
          containerRectWidth <= 0 ||
          !Number.isFinite(containerClientWidth) ||
          containerClientWidth <= 0
        ) {
          retryOrFail("split view container has no valid width");
          return;
        }

        const minWidth = parseFloat(getComputedStyle(leftPanel).minWidth);
        const maxWidth = containerClientWidth - minWidth;

        if (
          !Number.isFinite(minWidth) ||
          minWidth < 0 ||
          !Number.isFinite(maxWidth) ||
          maxWidth < minWidth
        ) {
          retryOrFail("Firefox split view width bounds are not ready");
          return;
        }

        // Match Firefox 156: the splitter controls the left panel and leaves
        // the right panel flexible.
        splitView.resetRightPanelWidth?.();

        const desiredWidth = ratio * containerRectWidth;
        const restoredWidth = Math.round(
          Math.min(maxWidth, Math.max(minWidth, desiredWidth))
        );

        leftPanel.setAttribute("width", String(restoredWidth));
        leftPanel.style.width = `${restoredWidth}px`;

        const ariaUpdate =
          gBrowser.tabpanels.updateSplitterAriaAttributes?.();

        if (ariaUpdate && typeof ariaUpdate.catch === "function") {
          ariaUpdate.catch(error => {
            console.error(
              `${LOG_PREFIX} splitter ARIA update failed:`,
              error
            );
          });
        }

        console.log(
          `${LOG_PREFIX} restored split ratio:`,
          ratio,
          "width:",
          restoredWidth,
          "operation:",
          operationId
        );
      } catch (error) {
        console.error(`${LOG_PREFIX} split ratio restore failed:`, error);
      }
    };

    try {
      scheduleNextFrame();
    } catch (error) {
      console.error(`${LOG_PREFIX} could not schedule split ratio restore:`, error);
    }
  }

  function getSplitTarget(splitView, clientX, clientY) {
    if (!splitView?.tabs?.length) {
      return null;
    }

    for (const tab of splitView.tabs) {
      const browser = tab.linkedBrowser;

      if (!browser) {
        continue;
      }

      const rect = browser.getBoundingClientRect();

      if (
        clientX >= rect.left &&
        clientX <= rect.right &&
        clientY >= rect.top &&
        clientY <= rect.bottom
      ) {
        return tab;
      }
    }

    return null;
  }

  /**
   * Срабатывает ДО того, как Firefox переключится
   * с Split View на нажатую обычную вкладку.
   */
  gBrowser.tabContainer.addEventListener(
    "mousedown",
    event => {
      if (event.button !== 0) {
        return;
      }

      const tab = getTabFromEvent(event);
      const splitView = gBrowser.activeSplitView;

      if (!isCurrentTab(tab) || !isCurrentSplitView(splitView)) {
        if (tab && splitView) {
          console.error(`${LOG_PREFIX} mousedown state rejected:`, {
            tabConnected: tab.isConnected,
            tabDocumentMatches: tab.ownerDocument === document,
            splitConnected: splitView.isConnected,
            splitDocumentMatches: splitView.ownerDocument === document
          });
        }
        pendingSplitView = null;
        pendingTab = null;
        return;
      }

      // Если нажали на одну из вкладок самого Split View —
      // нас это не интересует.
      if (splitContainsTab(splitView, tab)) {
        pendingSplitView = null;
        pendingTab = null;
        return;
      }

      // Запоминаем Split View ДО того,
      // как Firefox активирует другую вкладку.
      pendingSplitView = splitView;
      pendingTab = tab;
    },
    true
  );

  /**
   * Здесь обычная вкладка уже может стать selectedTab,
   * но ссылка на старый Split View у нас сохранена.
   */
  gBrowser.tabContainer.addEventListener(
    "dragstart",
    event => {
      const operationId = ++operationGeneration;
      const tab = getTabFromEvent(event);

      if (
        !tab ||
        tab !== pendingTab ||
        !isCurrentTab(tab) ||
        !isCurrentSplitView(pendingSplitView) ||
        splitContainsTab(pendingSplitView, tab)
      ) {
        console.error(`${LOG_PREFIX} dragstart state rejected:`, {
          hasTab: !!tab,
          matchesPendingTab: tab === pendingTab,
          tabConnected: tab?.isConnected,
          tabDocumentMatches: tab?.ownerDocument === document,
          splitConnected: pendingSplitView?.isConnected,
          splitDocumentMatches: pendingSplitView?.ownerDocument === document,
          tabAlreadyInSplit: splitContainsTab(pendingSplitView, tab)
        });
        dragSplitView = null;
        draggedTab = null;
        dragOperationId = 0;
        return;
      }

      dragSplitView = pendingSplitView;
      draggedTab = tab;
      dragOperationId = operationId;

      splitRestoredForDrag = false;

      console.log(
        `${LOG_PREFIX} drag started`,
        draggedTab,
        dragSplitView,
        "operation:",
        dragOperationId
      );
    },
    true
  );

  const browserArea =
    document.getElementById("browser") ||
    document.documentElement;

  /**
   * Когда перетаскиваемая вкладка попадает из tab bar
   * в область страницы — возвращаем старый Split View.
   */
  browserArea.addEventListener(
    "dragenter",
    event => {
      if (!dragSplitView || !draggedTab) {
        return;
      }

      if (!splitRestoredForDrag) {
        if (
          !isCurrentSplitView(dragSplitView) ||
          !isCurrentTab(draggedTab)
        ) {
          return;
        }

        const splitTabs = dragSplitView.tabs;

        if (
          splitTabs?.length &&
          isCurrentTab(splitTabs[0])
        ) {
          // Выбор любой вкладки Split View должен снова
          // показать обе его панели.
          gBrowser.selectedTab = splitTabs[0];

          splitRestoredForDrag = true;

          console.log(
            `${LOG_PREFIX} split restored`
          );
        }
      }

      event.preventDefault();
    },
    true
  );

  browserArea.addEventListener(
    "dragover",
    event => {
      if (
        !isCurrentSplitView(dragSplitView) ||
        !isCurrentTab(draggedTab)
      ) {
        clearHighlight();
        return;
      }

      const targetTab = getSplitTarget(
        dragSplitView,
        event.clientX,
        event.clientY
      );

      if (
        !isCurrentTab(targetTab) ||
        !splitContainsTab(dragSplitView, targetTab)
      ) {
        clearHighlight();
        return;
      }

      event.preventDefault();
      event.stopPropagation();

      if (event.dataTransfer) {
        event.dataTransfer.dropEffect = "move";
      }

      highlightTab(targetTab);
    },
    true
  );

  browserArea.addEventListener(
    "drop",
    event => {
      if (
        !isCurrentSplitView(dragSplitView) ||
        !isCurrentTab(draggedTab)
      ) {
        clearHighlight();
        return;
      }

      const targetTab = getSplitTarget(
        dragSplitView,
        event.clientX,
        event.clientY
      );

      if (
        !isCurrentTab(targetTab) ||
        !splitContainsTab(dragSplitView, targetTab)
      ) {
        clearHighlight();
        return;
      }

      event.preventDefault();
      event.stopPropagation();

      console.log(
        `${LOG_PREFIX} replacing`,
        targetTab,
        "with",
        draggedTab
      );

      try {
        const splitView = dragSplitView;
        const tabToReplace = targetTab;
        const tabToInsert = draggedTab;
        const operationId = dragOperationId;

        if (
          !isCurrentSplitView(splitView) ||
          !isCurrentTab(tabToReplace) ||
          !isCurrentTab(tabToInsert) ||
          !splitContainsTab(splitView, tabToReplace) ||
          splitContainsTab(splitView, tabToInsert) ||
          !Number.isInteger(operationId) ||
          operationId <= 0 ||
          operationGeneration !== operationId
        ) {
          console.error(`${LOG_PREFIX} drop state is no longer valid`);
          cleanup();
          return;
        }

        // Запоминаем положение разделителя ДО любых изменений.
        const savedSplitRatio = captureSplitRatio(splitView);

        if (!Number.isFinite(savedSplitRatio)) {
          console.error(`${LOG_PREFIX} could not capture split ratio`);
          cleanup();
          return;
        }

        console.log(
          `${LOG_PREFIX} saved split ratio:`,
          savedSplitRatio,
          "operation:",
          operationId
        );

        // Сохраняем вытесняемую вкладку как обычную.
        // Split View child tabs do not expose a usable _tPos in Firefox 156.
        // The native tab index getter remains valid for tabs inside the wrapper.
        const oldTabIndex = Number.isInteger(tabToReplace.index)
          ? tabToReplace.index
          : gBrowser.tabs.indexOf(tabToReplace);

        if (!Number.isInteger(oldTabIndex) || oldTabIndex < 0) {
          console.error(`${LOG_PREFIX} target tab has no valid tab index`);
          cleanup();
          return;
        }

        const preservedTab = gBrowser.duplicateTab(
          tabToReplace,
          true,
          {
            inBackground: true,
            tabIndex: oldTabIndex + 1
          }
        );

        if (
          !isCurrentTab(preservedTab) ||
          preservedTab === tabToReplace ||
          preservedTab === tabToInsert
        ) {
          console.error(
            `${LOG_PREFIX} duplicateTab did not preserve the target tab; replaceTab cancelled`
          );
          cleanup();
          return;
        }

        // Remove the temporary width/position/transform styles installed by
        // Firefox's tab-strip drag code before the tab changes DOM parent.
        resetNativeTabDragPresentation(tabToInsert);

        // Меняем вкладку в Split View.
        splitView.replaceTab(
          tabToReplace,
          tabToInsert
        );

        gBrowser.selectedTab = tabToInsert;

        // Возвращаем положение разделителя.
        restoreSplitRatio(
          splitView,
          tabToInsert,
          savedSplitRatio,
          operationId
        );
      } catch (error) {
        console.error(
          `${LOG_PREFIX} replaceTab failed:`,
          error
        );
      }

      cleanup();
    },
    true
  );

  function cleanup() {
    clearHighlight();

    pendingSplitView = null;
    pendingTab = null;

    dragSplitView = null;
    draggedTab = null;
    dragOperationId = 0;

    splitRestoredForDrag = false;
  }

  window.addEventListener(
    "dragend",
    () => {
      cleanup();
    },
    true
  );

  console.log(
    `${LOG_PREFIX} loaded`
  );
})();
