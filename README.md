project:
  name: Brainfuck CPU – INP Project 1
  course: INP (Design of Computer Systems)
  type: University assignment

description: >
  Implementation of a Brainfuck CPU / interpreter.
  The project simulates execution of the Brainfuck programming language
  according to the INP course specification.

structure:
  src: Source code of the Brainfuck CPU
  test: Test inputs and test cases
  requirements.txt: Python dependencies

features:
  - Brainfuck instruction processing (>, <, +, -, ., ,, [, ])
  - Memory tape simulation
  - Instruction pointer control
  - Loop handling
  - Error handling for invalid programs

requirements:
  language: Python 3.x
  dependencies_file: requirements.txt

installation:
  command: pip install -r requirements.txt

testing:
  location: test/
  description: Test cases for validating CPU behavior

notes:
  - Created for educational purposes
  - Follows INP assignment requirements

