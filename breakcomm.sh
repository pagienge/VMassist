#!/usr/bin/bash

  ip r del 169.254.169.254 
  ip r del 168.63.129.16 
    
  ip r add 168.63.129.16 via 127.0.0.1 dev lo
  ip r add 169.254.169.254 via 127.0.0.1 dev lo