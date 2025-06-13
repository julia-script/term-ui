import * as v from "valibot";

try {
  v.parse(v.string(), 2);
} catch (error) {
  console.log(error.stack);
}
