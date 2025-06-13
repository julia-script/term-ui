/**
 * InputState tracks the current state of keyboard and mouse inputs
 */

import {
  type ModifierState,
  MouseButtons,
} from "./types/events";

export interface MousePosition {
  x: number;
  y: number;
}

export interface MouseButtonState {
  pressed: boolean;
  pressStartTime: number;
  pressStartPosition: MousePosition | null;
}

export interface KeyState {
  pressed: boolean;
  pressStartTime: number;
  repeatCount: number;
}

export class InputState {
  // Mouse state
  private mousePosition: MousePosition = {
    x: 0,
    y: 0,
  };
  private mouseButtons: Map<
    number,
    MouseButtonState
  > = new Map();
  private buttonsPressed: number =
    MouseButtons.NONE;

  // Keyboard state
  private keysPressed: Map<string, KeyState> =
    new Map();
  private modifiers: ModifierState = {
    ctrlKey: false,
    shiftKey: false,
    altKey: false,
    metaKey: false,
  };

  // Drag detection threshold
  private dragThreshold = 5; // pixels

  constructor() {
    // Initialize mouse button states
    for (let i = 0; i < 3; i++) {
      this.mouseButtons.set(i, {
        pressed: false,
        pressStartTime: 0,
        pressStartPosition: null,
      });
    }
  }

  // Mouse methods
  updateMousePosition(
    x: number,
    y: number,
  ): void {
    this.mousePosition = { x, y };
  }

  getMousePosition(): MousePosition {
    return { ...this.mousePosition };
  }

  setMouseButtonPressed(
    button: number,
    pressed: boolean,
  ): void {
    const state = this.mouseButtons.get(button);
    if (!state) return;

    if (pressed && !state.pressed) {
      // Button just pressed
      state.pressed = true;
      state.pressStartTime = Date.now();
      state.pressStartPosition = {
        ...this.mousePosition,
      };

      // Update buttons bitmask
      if (button === 0)
        this.buttonsPressed |= MouseButtons.LEFT;
      else if (button === 1)
        this.buttonsPressed |=
          MouseButtons.MIDDLE;
      else if (button === 2)
        this.buttonsPressed |= MouseButtons.RIGHT;
    } else if (!pressed && state.pressed) {
      // Button just released
      state.pressed = false;
      state.pressStartTime = 0;
      state.pressStartPosition = null;

      // Update buttons bitmask
      if (button === 0)
        this.buttonsPressed &= ~MouseButtons.LEFT;
      else if (button === 1)
        this.buttonsPressed &=
          ~MouseButtons.MIDDLE;
      else if (button === 2)
        this.buttonsPressed &=
          ~MouseButtons.RIGHT;
    }
  }

  isMouseButtonPressed(button: number): boolean {
    return (
      this.mouseButtons.get(button)?.pressed ??
      false
    );
  }

  getMouseButtons(): number {
    return this.buttonsPressed;
  }

  isDragging(button = 0): boolean {
    const state = this.mouseButtons.get(button);
    if (
      !state ||
      !state.pressed ||
      !state.pressStartPosition
    ) {
      return false;
    }

    const dx =
      this.mousePosition.x -
      state.pressStartPosition.x;
    const dy =
      this.mousePosition.y -
      state.pressStartPosition.y;
    const distance = Math.sqrt(dx * dx + dy * dy);

    return distance > this.dragThreshold;
  }

  getMouseButtonPressedDuration(
    button: number,
  ): number {
    const state = this.mouseButtons.get(button);
    if (!state || !state.pressed) return 0;

    return Date.now() - state.pressStartTime;
  }

  // Keyboard methods
  setKeyPressed(
    key: string,
    code: string,
    pressed: boolean,
  ): void {
    if (pressed) {
      const existingState =
        this.keysPressed.get(code);
      if (existingState) {
        // Key is repeating
        existingState.repeatCount++;
      } else {
        // New key press
        this.keysPressed.set(code, {
          pressed: true,
          pressStartTime: Date.now(),
          repeatCount: 0,
        });
      }
    } else {
      // Key released
      this.keysPressed.delete(code);
    }

    // Update modifier states
    this.updateModifierFromKey(key, pressed);
  }

  isKeyPressed(code: string): boolean {
    return this.keysPressed.has(code);
  }

  getKeyPressedDuration(code: string): number {
    const state = this.keysPressed.get(code);
    if (!state) return 0;

    return Date.now() - state.pressStartTime;
  }

  getKeyRepeatCount(code: string): number {
    return (
      this.keysPressed.get(code)?.repeatCount ?? 0
    );
  }

  getPressedKeys(): string[] {
    return Array.from(this.keysPressed.keys());
  }

  // Modifier methods
  private updateModifierFromKey(
    key: string,
    pressed: boolean,
  ): void {
    switch (key) {
      case "Control":
        this.modifiers.ctrlKey = pressed;
        break;
      case "Shift":
        this.modifiers.shiftKey = pressed;
        break;
      case "Alt":
        this.modifiers.altKey = pressed;
        break;
      case "Meta":
        this.modifiers.metaKey = pressed;
        break;
    }
  }

  getModifiers(): ModifierState {
    return { ...this.modifiers };
  }

  // Utility methods
  clear(): void {
    // Clear mouse state
    this.mousePosition = { x: 0, y: 0 };
    this.buttonsPressed = MouseButtons.NONE;
    for (const state of this.mouseButtons.values()) {
      state.pressed = false;
      state.pressStartTime = 0;
      state.pressStartPosition = null;
    }

    // Clear keyboard state
    this.keysPressed.clear();
    this.modifiers = {
      ctrlKey: false,
      shiftKey: false,
      altKey: false,
      metaKey: false,
    };
  }

  setDragThreshold(pixels: number): void {
    this.dragThreshold = pixels;
  }
}
