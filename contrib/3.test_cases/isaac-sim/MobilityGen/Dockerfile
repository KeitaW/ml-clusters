FROM nvcr.io/nvidia/isaac-sim:5.1.0

COPY src/automated_mobilitygen.py /isaac-sim/scripts/

WORKDIR /isaac-sim

ENTRYPOINT ["/isaac-sim/python.sh", "/isaac-sim/scripts/automated_mobilitygen.py"]
