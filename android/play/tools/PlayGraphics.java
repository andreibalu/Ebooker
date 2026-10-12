import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/** Renders the Play icon (512px, 32-bit) and feature graphic (1024x500) from the iOS icon's
 *  geometry and colors. Usage: java PlayGraphics.java <AppIcon-1024.png> <out-dir> */
public class PlayGraphics {
    static final Color NAVY = new Color(0x122131), CREAM = new Color(0xF3EEE7), AMBER = new Color(0xE49A20);

    /** The bookmark and dot in AppIcon-1024 coordinates, scaled by s and offset to (x, y). */
    static void glyph(Graphics2D g, double x, double y, double s) {
        AffineTransform t = g.getTransform();
        g.translate(x, y); g.scale(s, s);
        Path2D mark = new Path2D.Double();
        mark.moveTo(387, 122); mark.lineTo(637, 122); mark.lineTo(637, 758); mark.lineTo(512, 653); mark.lineTo(387, 758); mark.closePath();
        g.setColor(CREAM); g.fill(mark);
        g.setColor(AMBER); g.fill(new Ellipse2D.Double(439.5, 746, 144, 144));
        g.setTransform(t);
    }

    static Graphics2D smooth(BufferedImage im) {
        Graphics2D g = im.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
        g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON);
        return g;
    }

    public static void main(String[] args) throws Exception {
        File out = new File(args[1]); out.mkdirs();

        // Icon: the shipping iOS artwork, downscaled into a 32-bit ARGB PNG as Play requires.
        BufferedImage source = ImageIO.read(new File(args[0]));
        BufferedImage icon = new BufferedImage(512, 512, BufferedImage.TYPE_INT_ARGB);
        Graphics2D gi = smooth(icon); gi.drawImage(source, 0, 0, 512, 512, null); gi.dispose();
        ImageIO.write(icon, "png", new File(out, "icon.png"));

        // Feature graphic: glyph left of center, wordmark and line to its right.
        BufferedImage fg = new BufferedImage(1024, 500, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = smooth(fg);
        g.setColor(NAVY); g.fillRect(0, 0, 1024, 500);
        double s = 0.38; // glyph spans y 122..890 -> ~292px tall
        glyph(g, 150 - 387 * s, 250 - 506 * s, s);
        Font serif = new Font("Baskerville", Font.PLAIN, 112);
        if (!serif.getFamily().equals("Baskerville")) serif = new Font(Font.SERIF, Font.PLAIN, 112);
        g.setFont(serif); g.setColor(CREAM);
        g.drawString("Unpaged", 330, 262);
        g.setFont(new Font("Helvetica Neue", Font.PLAIN, 30)); g.setColor(new Color(0xF3EEE7, false));
        g.setColor(new Color(243, 238, 231, 200));
        g.drawString("Your audiobooks. 20,000 free classics.", 334, 322);
        g.setColor(AMBER); g.fillRect(334, 352, 64, 4);
        g.dispose();
        ImageIO.write(fg, "png", new File(out, "featureGraphic.png"));
    }
}
