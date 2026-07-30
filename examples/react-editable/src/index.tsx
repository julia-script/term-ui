// Acceptance demo for the browser-feel selection/input slice:
// - click places the caret (WebKit-style caret-from-point)
// - drag selects, with the highlight correct across wrapped lines
// - arrows move the caret; shift extends; alt/ctrl jumps by word
// - the region is editable: type to insert, backspace/delete to remove
import TermUi from "@term-ui/react";

const App = () => {
  return (
    <view
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        padding: "1",
      }}
    >
      <text style={{ color: "gray" }}>
        click to place the caret · drag to select
        · shift+arrows extend · alt+arrows jump
        words
      </text>
      <view
        contentEditable
        style={{
          width: "40",
          borderStyle: "double",
          padding: "1",
          color: "white",
        }}
      >
        <text>
          Select me with the mouse or the
          keyboard. This text wraps across
          several lines so selections can span
          line boundaries, just like in a
          browser.
        </text>
      </view>
    </view>
  );
};

await TermUi.createRoot(<App />, {});
