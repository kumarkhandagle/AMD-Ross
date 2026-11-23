# AMD Ross Course – Source Codes

This folder contains the source files and supporting examples used in the hands-on demonstrations of the **AMD Ross for FPGA Design and Verification** course by **Namaste FPGA**.

The materials are organized section-wise so that learners can easily locate the files corresponding to each lecture, reproduce the demonstrations in AMD Vivado, and complete the practical assignments using AMD Ross.

## Section-wise code directory

| Section | Course topic | Source-code folder |
|---|---|---|
| 1 | AMD Ross Setup and Configuration | [Section-1](./Section-1/) |
| 2 | Vivado Project Management with AMD Ross | [Section-2](./Section-2/) |
| 3 | Getting Started with RTL Linting | [Section-3](./Section-3/) |
| 4 | Behavioral Simulation and RTL Debugging with Verilog and UVM | [Section-4](./Section-4/) |
| 5 | Code Coverage Analysis and Improvement | [Section-5](./Section-5/) |
| 6 | Synthesis & Gate Netlist | [Section-6](./Section-6/) |
| 7 | Implementation & Timings | [Section-7](./Section-7/) |
| 8 | Bitstream | [Section-8](./Section-8/) |

Section folders and materials will become available as the corresponding course content is published.

## How to use the files

1. Open the section folder corresponding to the lecture you are following.
2. Download the required files, or clone the repository:

   ```bash
   git clone https://github.com/kumarkhandagle/AMD-Ross.git
   ```

3. Open the supplied Vivado project, if available, or create a new project and add the relevant RTL files as **Design Sources** and testbench files as **Simulation Sources**.
4. Follow the lecture to run the appropriate workflow using **AMD Ross**, **Google Antigravity**, and **AMD Vivado**.
5. For assignments, apply your changes to a separate working copy so that the original course files remain available for comparison.

## Important notes

- Some examples intentionally contain RTL bugs or incomplete implementations for debugging demonstrations. A source file should not automatically be treated as a fully corrected reference design.
- The exact tool configuration, FPGA part, simulation top module, and any UVM library requirements depend on the corresponding lecture.
- Generated simulation files, logs, and synthesis reports may differ across Vivado versions and local environments.
- Preserve copyright and license notices included in individual source files.

**Course provider:** [Namaste FPGA](https://namaste-fpga.com/courses)  
**Repository:** [AMD-Ross](https://github.com/kumarkhandagle/AMD-Ross)
