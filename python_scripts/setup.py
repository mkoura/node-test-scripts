# setup.py
from os.path import join, dirname
from setuptools import setup, find_packages

install_requires = (
    'requests>=2.22.0',
)

excludes = (
    '*test*',
    '*local_settings*',
)

setup(name="Cardano Shelley e2e tests",
      version="0.1",
      packages=find_packages(exclude=excludes),
      install_requires=install_requires)
