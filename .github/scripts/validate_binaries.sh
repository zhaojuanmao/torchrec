#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.


export PYTORCH_CUDA_PKG=""

conda create -y -n build_binary python="${MATRIX_PYTHON_VERSION}"

conda run -n build_binary python --version

# Install pytorch, torchrec and fbgemm as per
# installation instructions on following page
# https://github.com/pytorch/torchrec#installations

if [[ ${MATRIX_GPU_ARCH_TYPE} = 'rocm' ]]; then
    echo "We don't support rocm"
    exit 0
fi

if [[ ${MATRIX_GPU_ARCH_TYPE} = 'cuda' ]]; then
    export CUDA_VERSION="cu124"
else
    export CUDA_VERSION="cpu"
fi

# figure out CUDA VERSION
if [[ ${MATRIX_GPU_ARCH_TYPE} = 'cuda' ]]; then
    if [[ ${MATRIX_GPU_ARCH_VERSION} = '11.8' ]]; then
        export CUDA_VERSION="cu118"
    elif [[ ${MATRIX_GPU_ARCH_VERSION} = '12.1' ]]; then
        export CUDA_VERSION="cu121"
    else
        export CUDA_VERSION="cu124"
    fi
else
    export CUDA_VERSION="cpu"
fi

# figure out URL
if [[ ${MATRIX_CHANNEL} = 'nightly' ]]; then
    export PYTORCH_URL="https://download.pytorch.org/whl/nightly/${CUDA_VERSION}"
elif [[ ${MATRIX_CHANNEL} = 'test' ]]; then
    export PYTORCH_URL="https://download.pytorch.org/whl/test/${CUDA_VERSION}"
elif [[ ${MATRIX_CHANNEL} = 'release' ]]; then
    export PYTORCH_URL="https://download.pytorch.org/whl/${CUDA_VERSION}"
fi

# install pytorch
# switch back to conda once torch nightly is fixed
# if [[ ${MATRIX_GPU_ARCH_TYPE} = 'cuda' ]]; then
#     export PYTORCH_CUDA_PKG="pytorch-cuda=${MATRIX_GPU_ARCH_VERSION}"
# fi
conda run -n build_binary pip install torch --index-url "$PYTORCH_URL"

# install fbgemm
conda run -n build_binary pip install fbgemm-gpu --index-url "$PYTORCH_URL"

# install requirements from pypi
conda run -n build_binary pip install torchmetrics==1.0.3

# install torchrec
conda run -n build_binary pip install torchrec --index-url "$PYTORCH_URL"

# Run small import test
conda run -n build_binary python -c "import torch; import fbgemm_gpu; import torchrec"

# check directory
ls -R

# check if cuda available
conda run -n build_binary python -c "import torch; print(torch.cuda.is_available())"

# check cuda version
conda run -n build_binary python -c "import torch; print(torch.version.cuda)"

# Finally run smoke test
# python 3.11 needs torchx-nightly
conda run -n build_binary pip install torchx-nightly iopath
if [[ ${MATRIX_GPU_ARCH_TYPE} = 'cuda' ]]; then
    conda run -n build_binary torchx run -s local_cwd dist.ddp -j 1 --gpu 2 --script test_installation.py
else
    conda run -n build_binary torchx run -s local_cwd dist.ddp -j 1 --script test_installation.py -- --cpu_only
fi


# redo for pypi release

if [[ ${MATRIX_CHANNEL} != 'release' ]]; then
    exit 0
else
    # Check version matches only for release binaries
    torchrec_version=$(conda run -n build_binary pip show torchrec | grep Version | cut -d' ' -f2)
    fbgemm_version=$(conda run -n build_binary pip show fbgemm_gpu | grep Version | cut -d' ' -f2)

    if [ "$torchrec_version" != "$fbgemm_version" ]; then
        echo "Error: TorchRec package version does not match FBGEMM package version"
        exit 1
    fi
fi

conda create -y -n build_binary python="${MATRIX_PYTHON_VERSION}"

conda run -n build_binary python --version

if [[ ${MATRIX_GPU_ARCH_VERSION} != '12.4' ]]; then
    exit 0
fi

echo "checking pypi release"
conda run -n build_binary pip install torch
conda run -n build_binary pip install fbgemm-gpu
conda run -n build_binary pip install torchrec

# Check version matching again for PyPI
torchrec_version=$(conda run -n build_binary pip show torchrec | grep Version | cut -d' ' -f2)
fbgemm_version=$(conda run -n build_binary pip show fbgemm_gpu | grep Version | cut -d' ' -f2)

if [ "$torchrec_version" != "$fbgemm_version" ]; then
    echo "Error: TorchRec package version does not match FBGEMM package version"
    exit 1
fi

# check directory
ls -R

# check if cuda available
conda run -n build_binary python -c "import torch; print(torch.cuda.is_available())"

# check cuda version
conda run -n build_binary python -c "import torch; print(torch.version.cuda)"

# python 3.11 needs torchx-nightly
conda run -n build_binary pip install torchx-nightly iopath

# Finally run smoke test
conda run -n build_binary torchx run -s local_cwd dist.ddp -j 1 --gpu 2 --script test_installation.py
