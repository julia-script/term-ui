import {
  init,
  type InitArgs,
  type Module,
} from "@term-ui/core";
import { loader } from "@term-ui/core/node";
import {
  Document,
  type DocumentOptions,
} from "@term-ui/dom";
import type { OpaqueRoot } from "react-reconciler";
import { ConcurrentRoot } from "react-reconciler/constants";
import { Viewport } from "./Viewport.js";
import { reconciler } from "./reconciler/reconciler.js";

/**
 * Options for creating a TermUi instance
 * @public
 */
export type TermUiOptions = InitArgs &
  DocumentOptions;

/**
 * Main class for Terminal UI rendering with React
 *
 * @remarks
 * TermUi provides the core functionality for rendering React components in terminal environments.
 * It handles document creation, rendering, and lifecycle management.
 *
 * @example
 * ```tsx
 * // Create a simple terminal UI app
 * TermUi.createRoot(<App />);
 * ```
 *
 * @public
 */
export class TermUi {
  private container: OpaqueRoot;

  /**
   * @internal
   * Private constructor - use {@link TermUi.createRoot} to create instances
   */
  private constructor(
    /**
     * The Document instance this TermUi renders to
     */
    public document: Document,
  ) {
    document.root.setStyle(`
      width: 100%;
      height: 100%;
    `);
    this.container = reconciler.createContainer(
      this,
      ConcurrentRoot,
      null,
      process.env.NODE_ENV === "development",
      true,
      "id",
      (error) => {
        console.error(error);
      },
      (error) => {
        console.error(error);
      },
      (error) => {
        console.error(error);
      },
      null,
    );
    document.writeStream.on(
      "resize",
      this.onResize,
    );
  }

  /**
   * @internal
   * Handler for resize events
   */
  private onResize = () => {
    this.render();
  };

  /**
   * Render the document to the terminal
   *
   * @remarks
   * This method computes the layout and paints the UI to the terminal.
   * It's automatically called on resize events, but can be manually triggered if needed.
   *
   * @public
   */
  render = () => {
    try {
      this.document.computeLayout();
      this.document.paint();
    } catch (error) {}
  };

  /**
   * Creates a new TermUi instance and renders the provided React element
   *
   * @param root - The React element to render
   * @param options - Configuration options for the terminal UI
   * @returns A promise that resolves to a TermUi instance
   *
   * @example
   * ```tsx
   * // Basic usage - defaults to process.stdin and process.stdout
   * const termUi = await TermUi.createRoot(<App />);
   *
   * // Later, to clean up:
   * termUi.dispose();
   * ```
   *
   * @public
   */
  static async createRoot(
    root: React.ReactNode,
    options: Partial<TermUiOptions> = {},
  ) {
    const module = await init({
      ...options,
      loader: options.loader ?? loader,
    });
    const document = new Document(
      module,
      options,
    );
    const tui = new TermUi(document);
    reconciler.updateContainer(
      <Viewport termUi={tui}>{root}</Viewport>,
      tui.container,
      null,
      () => {},
    );
    return tui;
  }

  /**
   * Cleans up resources used by the TermUi instance
   *
   * @remarks
   * Removes event listeners and disposes the document.
   * Call this method when you're done with the TermUi instance to prevent memory leaks.
   *
   * Note that if your application runs until process termination (like in a script that
   * exits when complete), explicit cleanup may not be necessary as the operating system
   * will reclaim all resources when the process ends.
   *
   * @public
   */
  dispose = () => {
    this.document.writeStream.off(
      "resize",
      this.onResize,
    );
    this.document.dispose();
  };
}
