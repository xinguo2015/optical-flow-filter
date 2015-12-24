/**
 * \file imagemodel.cu
 * \brief type declarations vision pipelines.
 * \copyright 2015, Juan David Adarve, ANU. See AUTHORS for more details
 * \license 3-clause BSD, see LICENSE for more details
 */

#include <exception>
#include <iostream>

#include "flowfilter/gpu/imagemodel.h"
#include "flowfilter/gpu/util.h"
#include "flowfilter/gpu/device/imagemodel_k.h"

namespace flowfilter {
    namespace gpu {

        //#################################################
        // ImageModel
        //#################################################
        ImageModel::ImageModel() :
            Stage() {
            __configured = false;
        }

        /**
         * \brief creates an image model stage with a given input image
         *
         * This constructor internally calles configure() so that the
         * stage is ready to perform computations.
         */
        ImageModel::ImageModel(flowfilter::gpu::GPUImage inputImage) :
            Stage() {
            
            __configured = false;
            setInputImage(inputImage);
            configure();
        }

        ImageModel::~ImageModel() {

            std::cout << "ImageModel::~ImageModel()" << std::endl;

            // nothing to do...
            // delete __inputImageTexture;
        }

        void ImageModel::configure() {

            int height = __inputImage.height();
            int width = __inputImage.width();

            std::cout << "ImageModel::configure(): [" << height << ", " << width << ", " << __inputImage.depth() << "] size: " << __inputImage.itemSize() << " pitch: " << __inputImage.pitch() << std::endl;

            if(__inputImage.itemSize() == sizeof(unsigned char)) {
                // wraps __inputImage with normalized texture
                __inputImageTexture = GPUTexture(__inputImage, cudaChannelFormatKindUnsigned, cudaReadModeNormalizedFloat);
            } else {
                // wraps __inputImage with float texture
                __inputImageTexture = GPUTexture(__inputImage, cudaChannelFormatKindFloat);    
            }
            

            // 2-channel[float] filtered image
            __imageFiltered = GPUImage(height, width, 2, sizeof(float));
            __imageFilteredTexture = GPUTexture(__imageFiltered, cudaChannelFormatKindFloat);

            // 1-channel[float] constant model parameter
            __imageConstant = GPUImage(height, width, 1, sizeof(float));

            // 2-channel[float] gradient model parameter
            __imageGradient = GPUImage(height, width, 2, sizeof(float));

            // configure block and grid sizes
            __block = dim3(32, 32, 1);
            configureKernelGrid(height, width, __block, __grid);

            __configured = true;
        }

        /**
         * \brief performs computation of brightness parameters
         */
        void ImageModel::compute() {

            // startTiming();

            if(!__configured) {
                std::cerr << "ERROR: ImageModel::compute() stage not configured." << std::endl;
                exit(-1);
            }

            // prefilter
            imagePrefilter_k<<<__grid, __block, 0, __stream>>> (
                __inputImageTexture.getTextureObject(), __inputImage.wrap<unsigned char>(),
                __imageFiltered.wrap<float2>());

            // compute brightness parameters
            imageModel_k<<<__grid, __block, 0, __stream>>> (
                __imageFilteredTexture.getTextureObject(),
                __imageConstant.wrap<float>(),
                __imageGradient.wrap<float2>());

            // stopTiming();
        }


        //#########################
        // Pipeline stage inputs
        //#########################
        void ImageModel::setInputImage(flowfilter::gpu::GPUImage img) {

            // check if image is a gray scale image with pixels 1 byte long
            if(img.depth() != 1) {
                std::cerr << "ERROR: ImageModel::setInputImage(): image depth should be 1: " << img.depth() << std::endl;
                throw std::exception();
            }

            if(img.itemSize() != sizeof(unsigned char) && img.itemSize() != sizeof(float)) {
                std::cerr << "ERROR: sizeof(uchar): " << sizeof(unsigned char) << std::endl;
                std::cerr << "ERROR: ImageModel::setInputImage(): item size should be 1 or 4: " << img.itemSize() << std::endl;
                throw std::exception();
            }

            __inputImage = img;
        }

        //#########################
        // Pipeline stage outputs
        //#########################
        flowfilter::gpu::GPUImage ImageModel::getImageConstant() {

            return __imageConstant;
        }

        flowfilter::gpu::GPUImage ImageModel::getImageGradient() {

            return __imageGradient;
            // return __imageFiltered;
        }


    }; // namespace gpu
}; // namespace flowfilter