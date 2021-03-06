
import R from "ramda";
import deepFreeze_ from "deep-freeze";

const trimmedProp = R.compose(R.trim, String, R.or(R.__, ""), R.prop);

export const getCellValue = R.compose(
    R.either(trimmedProp("customValue"), trimmedProp("originalValue")),
    R.or(R.__, {})
);

const callPreventDefault = R.invoker(0, "preventDefault");
export const didPressEnter = R.compose(R.equals("Enter"), R.prop("key"));

export function preventDefault(fn=R.identity) {
    return (e) => {
        callPreventDefault(e);
        return fn(e);
    };
}

export function onEnterKey(fn) {
    return e => {
        if (didPressEnter(e)) {
            callPreventDefault(e);
            fn(e);
        }
    };
}

// Deep freezing is slow and makes things slow so skip it in production
export const deepFreeze = process.env.NODE_ENV !== "production" ? deepFreeze_ : R.identity;
