import tensorflow as tf

interpreter = tf.lite.Interpreter(
    model_path="best_int8.tflite"
)

print("========== MODEL INPUTS ==========")

for i, tensor in enumerate(interpreter.get_input_details()):
    print("Input:", i)
    print("  index:", tensor["index"])
    print("  name:", tensor["name"])
    print("  shape:", tensor["shape"])
    print("  shape_signature:", tensor["shape_signature"])
    print("  dtype:", tensor["dtype"])

print("\n========== MODEL OUTPUTS ==========")

for i, tensor in enumerate(interpreter.get_output_details()):
    print("Output:", i)
    print("  index:", tensor["index"])
    print("  name:", tensor["name"])
    print("  shape:", tensor["shape"])
    print("  dtype:", tensor["dtype"])