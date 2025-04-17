import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

def generate_blob_image(size=512, num_blobs=10, blur_radius=30):
    # Create a white background
    image = np.ones((size, size), dtype=np.float32)
    
    # Generate random blobs
    for _ in range(num_blobs):
        # Random position
        x = np.random.randint(0, size)
        y = np.random.randint(0, size)
        
        # Random blob size
        radius = np.random.randint(150, 300)
        intensity = np.random.uniform(0.6, 1.0)
        
        # Create coordinate grids
        y_grid, x_grid = np.ogrid[:size, :size]
        
        # Calculate distances from center
        distances = np.sqrt((x_grid - x)**2 + (y_grid - y)**2)
        
        # Create blob with smooth falloff
        blob = np.exp(-(distances**2)/(2*(radius/3)**2)) * intensity
        
        # Multiply the current image with the inverted blob
        image *= (1 - blob)

    # Apply Gaussian blur for smoother appearance
    image = gaussian_filter(image, sigma=blur_radius/10)
    
    # Convert to uint8 format (0-255)
    image = (image * 255).astype(np.uint8)
    
    # Create and save PIL Image
    img = Image.fromarray(image)
    img.save('random_blobs.png')
    
def pixel_to_multiplier(pixel_value):
    """
    Convert a grayscale pixel value (0-255) to a price multiplier (1.0-3.0)
    Dark areas will have higher multipliers, light areas will have lower multipliers
    """
    # Normalize pixel value to 0-1 range and invert
    normalized = 1 - (pixel_value / 255.0)
    # Map 0-1 range to 1.0-3.0 range
    multiplier = 1.0 + normalized * 2.0
    return multiplier

def parse_price_multipliers(image_path='random_blobs.png'):
    """
    Parse the generated image and return a 2D array of price multipliers
    """
    # Open and convert image to grayscale
    img = Image.open(image_path).convert('L')
    width, height = img.size
    
    # Create numpy array to store multipliers
    multipliers = np.zeros((height, width))
    
    # Get pixel data
    pixels = np.array(img)
    
    # Convert all pixels to multipliers
    multipliers = pixel_to_multiplier(pixels)
    
    return multipliers
    


if __name__ == "__main__":
    # generate_blob_image()
    multipliers = parse_price_multipliers()
    print(f"Price multiplier at coordinate (100,100): {multipliers[0,0]:.2f}")
    print(multipliers)