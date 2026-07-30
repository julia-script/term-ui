# @term-ui/dom

A modern terminal UI DOM implementation for building interactive terminal applications.

## Features

- **DOM-like API**: Create, manipulate, and style terminal UI elements using a familiar DOM-like API
- **Event Handling**: Add event listeners for terminal events like clicks and hover
- **Flexible Styling**: Set styles with CSS-like syntax including borders, colors, and layout
- **Responsive Layouts**: Support for percentage-based sizing and flexible layouts
- **Efficient Rendering**: Optimized rendering algorithm for terminal environments

## Installation

```bash
# npm
npm install @term-ui/dom

# pnpm
pnpm add @term-ui/dom

# yarn
yarn add @term-ui/dom
```

## Basic Usage

```typescript
import { initFromFile } from "@term-ui/core/node";
import { Document } from "@term-ui/dom";

// Initialize the WebAssembly module
const module = await initFromFile();

// Create a new document
const document = new Document(module, {
  size: {
    width: "100%",
    height: "100%",
  },
});

// Style the root element
document.root.setStyle(`
  color: white; 
  border-style: rounded; 
  padding: 1;
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
`);

// Create and style a button
const button = document.createElement("text");
button.setStyle(`
  border-style: double; 
  text-align: center;
  width: 30;
  border-color: white;
  cursor: pointer;
`);
button.setText("Click me");
document.root.appendChild(button);

// Add event listeners
button.addEventListener("click", () => {
  button.setText("Thank you! 🎉");
  document.render(true);
  setTimeout(() => {
    button.setText("Click me");
    document.render(true);
  }, 3000);
});

// Initial render
document.render(true);
```

## API Reference

### Document

The main container for the terminal UI.

```typescript
const document = new Document(module, {
  size: { width: string | number, height: string | number }
});
```

## Examples

Check out the [examples](https://github.com/juliaortiz/term-ui/tree/main/examples) directory for more complex examples and use cases.

## License

MIT
