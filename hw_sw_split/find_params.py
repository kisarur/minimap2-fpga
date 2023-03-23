import numpy as np
from sklearn.linear_model import LinearRegression
import sys

if len(sys.argv) != 2:
	print("Usage: python3 " + sys.argv[0] + " <timing_data_file>")
	exit(1)

timing_data_file = sys.argv[1]
timing_data = np.genfromtxt(timing_data_file, delimiter='\t')

hw_x = timing_data[:, [0, 1]]
hw_y = timing_data[:, [3]]

sw_x = timing_data[:, [2]]
sw_y = timing_data[:, [4]]

print("----------------------")
print("HW/SW split parameters")
print("----------------------")

hw_regression_model = LinearRegression()
hw_regression_model.fit(hw_x, hw_y)
r_square_hw = hw_regression_model.score(hw_x, hw_y)
print("K1_HW\t:", hw_regression_model.coef_[0, 0])
print("K2_HW\t:", hw_regression_model.coef_[0, 1])
print("C_HW\t:", hw_regression_model.intercept_[0])

sw_regression_model = LinearRegression()
sw_regression_model.fit(sw_x, sw_y)
r_square_sw = sw_regression_model.score(sw_x, sw_y)
print("K_SW\t:", sw_regression_model.coef_[0, 0])
print("C_SW\t:", sw_regression_model.intercept_[0])
print("")

print("Model accuracy information:")
print("R^2 for HW model :", r_square_hw)
print("R^2 for SW model :", r_square_sw)

