import TermUi from "@term-ui/react";
import {
  type PropsWithChildren,
  useState,
} from "react";
import { devtools } from "@term-ui/dom/devtools";

const VerticalSegment = ({
  x,
  y,
  on,
}: {
  x: number;
  y: number;
  on: boolean;
}) => {
  if (!on) {
    return null;
  }
  return (
    <view
      style={{
        position: "absolute",
        whiteSpace: "pre",
        left: x,
        top: y,
      }}
      children={"█\n▀"}
    />
  );
};
const HorizontalSegment = ({
  x,
  y,
  on,
}: {
  x: number;
  y: number;
  on: boolean | 0 | 1;
}) => {
  if (!on) {
    return null;
  }
  return (
    <view
      style={{
        position: "absolute",
        left: x,
        top: y,
        whiteSpace: "pre"
      }}
      children={"▄▄▄▄"}
    />
  );
};
const SEGMENT_MAP: Record<
  string,
  [
    a: number,
    b: number,
    c: number,
    d: number,
    e: number,
    f: number,
    g: number,
  ]
> = {
  // A B C D E F G,
  0: [1, 1, 1, 1, 1, 1, 0],
  1: [0, 1, 1, 0, 0, 0, 0],
  2: [1, 1, 0, 1, 1, 0, 1],
  3: [1, 1, 1, 1, 0, 0, 1],
  4: [0, 1, 1, 0, 0, 1, 1],
  5: [1, 0, 1, 1, 0, 1, 1],
  6: [1, 0, 1, 1, 1, 1, 1],
  7: [1, 1, 1, 0, 0, 0, 0],
  8: [1, 1, 1, 1, 1, 1, 1],
  9: [1, 1, 1, 1, 0, 1, 1],
  // To be able to display "ERR"
  E: [1, 0, 0, 1, 1, 1, 1],
  R: [1, 0, 0, 0, 1, 1, 0],
  // To be able to display "INF"
  I: [0, 1, 1, 0, 0, 0, 0],
  N: [1, 1, 1, 0, 1, 1, 0],
  F: [1, 0, 0, 0, 1, 1, 1],
  " ": [0, 0, 0, 0, 0, 0, 0],
  "-": [0, 0, 0, 0, 0, 0, 1],
  "*": [1, 1, 1, 1, 1, 1, 1],
  ".": [0, 0, 0, 0, 0, 0, 0],
} as const;

const SegmentDisplay = ({
  char,
  color,
}: {
  char: keyof typeof SEGMENT_MAP;
  color?: string;
}) => {
  const [a, b, c, d, e, f, g] = SEGMENT_MAP[
    char
  ] ?? [0, 0, 0, 0, 0, 0, 0];
  if (char === ".") {
    return (
      <view
        style={{
          height: 5,
          width: 2,
        }}
      >
        {/* DP */}
        <text
          style={{
            position: "absolute",
            whiteSpace: "pre",
            left: 1,
            top: 4,
            color,
          }}
        >
          {"▄"}
        </text>
      </view>
    );
  }
  return (
    <view
      style={{
        whiteSpace: "pre",
        height: 5,
        width: 6,
        color,
      }}
    >
      {/* A */}
      <HorizontalSegment x={1} y={0} on={!!a} />
      {/* B */}
      <VerticalSegment x={5} y={1} on={!!b} />
      {/* C */}
      <VerticalSegment x={5} y={3} on={!!c} />
      {/* D */}
      <HorizontalSegment x={1} y={4} on={!!d} />
      {/* E */}
      <VerticalSegment x={0} y={3} on={!!e} />
      {/* F */}
      <VerticalSegment x={0} y={1} on={!!f} />
      {/* G */}
      <HorizontalSegment x={1} y={2} on={!!g} />
    </view>
  );
};
const borderColor = "rgba(74, 0, 91, 0.5)";
const borderColorDarker = "rgba(74, 0, 91, 1)";
const borderColorLighter = "rgba(74, 0, 91, 0.1)";

const displayBackgroundColor =
  "rgba(255, 255, 255, 0.2)";

const textColor = "rgba(74, 0, 91, 0.8)";

const digitsColor = "rgba(251, 115, 100,1)";
const digitsColorLighter =
  "rgba(251, 115, 100, 0.8)";
const lastColumnColor = "#fb7364";

const SegmentDisplayPanel = ({
  number,
  color,
}: {
  number: string;
  color?: string;
}) => {
  return (
    <view
      style={{
        display: "flex",
        flexDirection: "row",
        gap: 1,
      }}
    >
      {number.split("").map((char, i) => {
        const segmentChar =
          char as keyof typeof SEGMENT_MAP;
        return (
          <SegmentDisplay
            key={`${i}-${char}`}
            char={segmentChar}
            color={color}
          />
        );
      })}
    </view>
  );
};

const CalculatorButton = ({
  children,
  onClick,
  style,
  activeStyles = {
    borderColor: borderColorDarker,
    backgroundColor: borderColorLighter,
    color: textColor,
  },
  hoverStyles = {
    borderColor: borderColorDarker,
    color: textColor,
  },
}: PropsWithChildren<{
  onClick: () => void;
  activeStyles?: React.CSSProperties;
  hoverStyles?: React.CSSProperties;
  style?: React.CSSProperties;
}>) => {
  const [isActive, setIsActive] = useState(false);
  const [isHovered, setIsHovered] =
    useState(false);

  return (
    <view
      onMouseDown={() => setIsActive(true)}
      onMouseUp={() => setIsActive(false)}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      style={{
        height: 5,
        borderStyle: "rounded",
        borderColor,
        borderWidth: 1,
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        fontWeight: "bold",
        flexGrow: 1,
        flexShrink: 0,
        flexBasis: "25%",
        color: "rgba(74, 0, 91, 0.8)",
        cursor: "pointer",

        ...(style ?? {}),
        ...(isHovered ? (hoverStyles ?? {}) : {}),
        ...(isActive ? (activeStyles ?? {}) : {}),
      }}
      onClick={onClick}
    >
      <text>{children}</text>
    </view>
  );
};
const Calculator = () => {
  const [display, setDisplay] = useState("0");
  const [storedValue, setStoredValue] = useState<
    number | null
  >(null);
  const [
    waitingForOperand,
    setWaitingForOperand,
  ] = useState(false);
  const [pendingOperator, setPendingOperator] =
    useState<string | null>(null);

  // Maximum number of characters to display
  const MAX_DISPLAY_LENGTH = 6;

  const calculate = (
    rightOperand: number,
    pendingOperator: string,
  ): number => {
    const leftOperand = storedValue ?? 0;

    switch (pendingOperator) {
      case "+":
        return leftOperand + rightOperand;
      case "-":
        return leftOperand - rightOperand;
      case "×":
        return leftOperand * rightOperand;
      case "÷":
        if (rightOperand === 0) {
          return Number.NaN;
        }
        return leftOperand / rightOperand;
      default:
        return rightOperand;
    }
  };

  // Convert numerical results to display strings
  const formatDisplayValue = (
    value: number,
  ): string => {
    if (Number.isNaN(value)) {
      return "ERR";
    }

    if (!Number.isFinite(value)) {
      return value > 0 ? "INF" : "-INF";
    }

    // Handle floating-point numbers with proper decimal place formatting
    const isFloat = value % 1 !== 0;
    if (isFloat) {
      // Convert to string first to check the integer part length
      const stringValue = `${value}`;
      const parts = stringValue.split(".");
      const integerPart = parts[0] || "";

      // Calculate how many decimal places we can display
      // Account for the decimal point itself in the calculation
      const maxDecimalPlaces =
        MAX_DISPLAY_LENGTH -
        integerPart.length -
        1;

      if (maxDecimalPlaces <= 0) {
        // No room for decimal places, check if integer part fits
        return integerPart.length >
          MAX_DISPLAY_LENGTH
          ? "ERR"
          : integerPart;
      }

      // Format with calculated decimal places
      const formattedValue = value.toFixed(
        maxDecimalPlaces,
      );

      // Trim trailing zeros while keeping at least one digit after decimal
      const trimmedValue = formattedValue
        .replace(/(\.\d*?)0+$/, "$1")
        .replace(/\.$/, "");

      // Check if the result still fits
      return trimmedValue.length >
        MAX_DISPLAY_LENGTH
        ? "ERR"
        : trimmedValue;
    }

    // For integers, just convert to string and check length
    const stringValue = `${value}`;
    return stringValue.length > MAX_DISPLAY_LENGTH
      ? "ERR"
      : stringValue;
  };

  const onClick = (button: string) => {
    if (!button) {
      return;
    }
    switch (button) {
      case "AC": {
        setDisplay("0");
        setStoredValue(null);
        setWaitingForOperand(false);
        setPendingOperator(null);
        break;
      }

      case "+/-": {
        const value = Number.parseFloat(display);
        if (value !== 0) {
          setDisplay(
            value > 0
              ? `-${value}`
              : `${Math.abs(value)}`,
          );
        }
        break;
      }

      case "%": {
        const currentValue =
          Number.parseFloat(display);
        setDisplay(`${currentValue / 100}`);
        setWaitingForOperand(true);
        break;
      }

      case "+":
      case "-":
      case "×":
      case "÷": {
        const operand =
          Number.parseFloat(display);

        if (
          pendingOperator !== null &&
          !waitingForOperand
        ) {
          const result = calculate(
            operand,
            pendingOperator,
          );
          setDisplay(formatDisplayValue(result));
          setStoredValue(
            Number.isFinite(result)
              ? result
              : null,
          );
        } else {
          setStoredValue(operand);
        }

        setPendingOperator(button);
        setWaitingForOperand(true);
        break;
      }

      case "=": {
        if (pendingOperator === null) {
          return;
        }

        const operand2 =
          Number.parseFloat(display);
        const result = calculate(
          operand2,
          pendingOperator,
        );

        setDisplay(formatDisplayValue(result));
        setStoredValue(
          Number.isFinite(result) ? result : null,
        );
        setPendingOperator(null);
        setWaitingForOperand(true);
        break;
      }

      case ".": {
        if (waitingForOperand) {
          setDisplay("0.");
          setWaitingForOperand(false);
        } else if (
          !display.includes(".") &&
          display.length < MAX_DISPLAY_LENGTH
        ) {
          setDisplay(`${display}.`);
        }
        break;
      }

      default: {
        // Digits 0-9
        const digit = button;

        if (waitingForOperand) {
          setDisplay(digit);
          setWaitingForOperand(false);
        } else {
          // Don't add more digits if we've reached the maximum length
          if (
            display.length >= MAX_DISPLAY_LENGTH
          ) {
            break;
          }

          setDisplay(
            display === "0"
              ? digit
              : `${display}${digit}`,
          );
        }
        break;
      }
    }
  };

  return (
    <view
      style={{
        width: "100%",
        display: "flex",
        maxWidth: 52,
        height: 39,
        margin: "auto",
        borderStyle: "rounded",
        flexDirection: "column",
        borderColor,
        backgroundColor:
          "rgba(255, 255, 255, 0.3)",
        padding: "1",
      }}
    >
      <text
        style={{
          position: "absolute",
          top: 0,
          right: 2,
          color: textColor,
          fontWeight: "bold",
        }}
      >
        @term-ui/react
      </text>
      <view
        style={{
          padding: "1",
          backgroundColor: displayBackgroundColor,
          borderColor,
          borderStyle: "rounded",
          display: "flex",

          flexDirection: "row",
          justifyContent: "end",
          gap: 1,
          flexWrap: "wrap",
        }}
      >
        <SegmentDisplayPanel
          number={display}
          color={
            waitingForOperand
              ? digitsColorLighter
              : digitsColor
          }
        />
      </view>
      <view
        style={{
          display: "flex",
          flexDirection: "row",
          // gap: 1,
        }}
      >
        {["AC", "+/-", "%", "÷"].map(
          (text, i) => (
            <CalculatorButton
              key={text}
              onClick={() => onClick(text)}
              style={
                i === 3
                  ? {
                      backgroundColor:
                        lastColumnColor,
                    }
                  : {}
              }
            >
              {text}
            </CalculatorButton>
          ),
        )}
      </view>
      <view
        style={{
          display: "flex",
        }}
      >
        {["7", "8", "9", "×"].map((text, i) => (
          <CalculatorButton
            key={text}
            onClick={() => onClick(text)}
            style={
              i === 3
                ? {
                    backgroundColor:
                      lastColumnColor,
                  }
                : {}
            }
          >
            {text}
          </CalculatorButton>
        ))}
      </view>
      <view
        style={{
          display: "flex",
        }}
      >
        {["4", "5", "6", "-"].map((text, i) => (
          <CalculatorButton
            key={text}
            onClick={() => onClick(text)}
            style={
              i === 3
                ? {
                    backgroundColor:
                      lastColumnColor,
                  }
                : {}
            }
          >
            {text}
          </CalculatorButton>
        ))}
      </view>
      <view
        style={{
          display: "flex",
        }}
      >
        {["1", "2", "3", "+"].map((text, i) => (
          <CalculatorButton
            key={text}
            onClick={() => onClick(text)}
            style={
              i === 3
                ? {
                    backgroundColor:
                      lastColumnColor,
                  }
                : {}
            }
          >
            {text}
          </CalculatorButton>
        ))}
      </view>
      <view
        style={{
          display: "flex",
          color: "rgba(74, 0, 91, 0.8)",
        }}
      >
        {["", "0", ".", "="].map((text, i) => {
          return (
            <CalculatorButton
              key={text}
              onClick={() => onClick(text)}
              style={
                i === 3
                  ? {
                      backgroundColor:
                        lastColumnColor,
                    }
                  : {}
              }
            >
              {text}
            </CalculatorButton>
          );
        })}
      </view>
    </view>
  );
};

const App = () => {
  return (
    <view
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        overflow: "scroll",
        padding: "1",
        backgroundColor:
          "radial-gradient(circle at top left,#e66465, #9198e5)",
      }}
    >
      <Calculator />
      
    </view>
  );
};

await TermUi.createRoot(<App />, {
  size: {
    width: "100%",
    height: "100%",
  },
});
