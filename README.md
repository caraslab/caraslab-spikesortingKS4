# CarasLab-SpikeSortingKS2

Pipeline for spike sorting multi-channel data acquired with TDT and Intan hardware.

Preprocessing steps convert data from native formats (Synapse or OpenEphysGUI) to .mat and/or .dat files. Files are then common median referenced and high-pass filtered, and run through Kilosort2 for sorting. 
This version runs with the modified Kilosort2 code also present in this repository. 

Required before running for the first time:
- npy-matlab (https://github.com/kwikteam/npy-matlab)
- Kilosort4: install Kilosort4 according to the developers' instructions (https://github.com/MouseLand/Kilosort).
- Don't forget to reinstall torch
```
pip uninstall torch
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
```
- Copy the modified run_kilosort.py file into your conda path (e.g., /home/user/miniconda3/envs/kilosort/lib/python3.9/site-packages/kilosort)