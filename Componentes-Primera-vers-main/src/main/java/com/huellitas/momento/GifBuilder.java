package com.huellitas.momento;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageTypeSpecifier;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.metadata.IIOInvalidTreeException;
import javax.imageio.metadata.IIOMetadata;
import javax.imageio.metadata.IIOMetadataNode;
import javax.imageio.stream.ImageOutputStream;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Iterator;
import java.util.List;

/**
 * Arma un GIF animado a partir de una lista de frames JPEG en memoria.
 * Usa solo javax.imageio del JDK, sin dependencias externas ni ffmpeg.
 */
public final class GifBuilder {

    private GifBuilder() {}

    /**
     * Convierte una lista de frames JPEG en un GIF animado.
     *
     * @param frames   bytes JPEG de cada fotograma.
     * @param delayMs  tiempo entre frames en milisegundos.
     * @return bytes del GIF, o null si falla.
     */
    public static byte[] construir(List<byte[]> frames, int delayMs) {
        if (frames == null || frames.isEmpty()) return null;

        int delayCentesimas = Math.max(delayMs / 10, 1);

        Iterator<ImageWriter> iter = ImageIO.getImageWritersBySuffix("gif");
        if (!iter.hasNext()) return null;
        ImageWriter writer = iter.next();

        try (ByteArrayOutputStream baos = new ByteArrayOutputStream();
             ImageOutputStream ios = ImageIO.createImageOutputStream(baos)) {

            writer.setOutput(ios);
            writer.prepareWriteSequence(null);

            boolean primero = true;
            for (byte[] jpegBytes : frames) {
                if (jpegBytes == null || jpegBytes.length == 0) continue;

                BufferedImage img;
                try (ByteArrayInputStream bais = new ByteArrayInputStream(jpegBytes)) {
                    img = ImageIO.read(bais);
                } catch (IOException e) {
                    continue;
                }
                if (img == null) continue;

                ImageWriteParam param = writer.getDefaultWriteParam();
                IIOMetadata metadata = writer.getDefaultImageMetadata(
                        ImageTypeSpecifier.createFromRenderedImage(img), param);

                configurarMetadataGif(metadata, delayCentesimas, primero);
                writer.writeToSequence(new IIOImage(img, null, metadata), param);
                primero = false;
            }

            writer.endWriteSequence();
            return baos.size() > 0 ? baos.toByteArray() : null;

        } catch (IOException e) {
            return null;
        } finally {
            writer.dispose();
        }
    }

    private static void configurarMetadataGif(IIOMetadata metadata, int delayCentesimas, boolean primero)
            throws IIOInvalidTreeException {

        String format = metadata.getNativeMetadataFormatName();
        IIOMetadataNode root = (IIOMetadataNode) metadata.getAsTree(format);

        IIOMetadataNode gce = getOrCreate(root, "GraphicControlExtension");
        gce.setAttribute("delayTime", String.valueOf(delayCentesimas));
        gce.setAttribute("disposalMethod", "doNotDispose");
        gce.setAttribute("userInputFlag", "FALSE");
        gce.setAttribute("transparentColorFlag", "FALSE");
        gce.setAttribute("transparentColorIndex", "0");

        if (primero) {
            IIOMetadataNode appExts = getOrCreate(root, "ApplicationExtensions");
            IIOMetadataNode appExt = new IIOMetadataNode("ApplicationExtension");
            appExt.setAttribute("applicationID", "NETSCAPE");
            appExt.setAttribute("authenticationCode", "2.0");
            appExt.setUserObject(new byte[]{0x1, 0x0, 0x0});
            appExts.appendChild(appExt);
        }

        metadata.setFromTree(format, root);
    }

    private static IIOMetadataNode getOrCreate(IIOMetadataNode root, String nodeName) {
        int n = root.getLength();
        for (int i = 0; i < n; i++) {
            if (root.item(i).getNodeName().equalsIgnoreCase(nodeName)) {
                return (IIOMetadataNode) root.item(i);
            }
        }
        IIOMetadataNode node = new IIOMetadataNode(nodeName);
        root.appendChild(node);
        return node;
    }
}
